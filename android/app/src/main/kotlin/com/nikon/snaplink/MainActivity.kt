package com.nikon.snaplink

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.RouteInfo
import android.net.wifi.WifiManager
import android.media.MediaScannerConnection
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.util.Log
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.app.Activity
import android.content.ContentValues
import android.net.Uri
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetAddress
import java.security.MessageDigest
import java.util.concurrent.Executors
import androidx.core.content.FileProvider

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.nikon.snaplink/native_camera"
    // 媒体 I/O 全局串行，最多一个任务；若并行导出成为瓶颈，可改为按 URI 串行。
    private val mediaExecutor = Executors.newSingleThreadExecutor()
    private val TAG = "SnapLinkNative"
    private val REQUEST_PICK_IMAGE = 1001
    private val ACTION_USB_PERMISSION = "com.nikon.snaplink.USB_PERMISSION"
    private var pendingPickResult: MethodChannel.Result? = null

    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var cameraNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private var boundCameraNetwork: Network? = null

    // Bluetooth
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var activeGatt: BluetoothGatt? = null
    private var isScanning = false
    private val scannedDevices = mutableMapOf<String, Map<String, Any>>()
    private var bleStatus = "disconnected"
    private var bleConnectedDeviceName: String? = null

    // USB PTP
    private var usbManager: UsbManager? = null
    private val usbSessions = mutableMapOf<String, UsbPtpSession>()
    private var pendingUsbPermissionResult: MethodChannel.Result? = null
    private var pendingUsbPermissionDeviceName: String? = null
    private var usbPermissionReceiver: BroadcastReceiver? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bm?.adapter
        usbManager = getSystemService(Context.USB_SERVICE) as? UsbManager

        // 请求关键运行时权限 (定位/近距离设备，以便系统允许读取 Wi-Fi SSID 与扫描 BLE)
        requestRuntimePermissions()

        // 预注册相机专用网络回调 (允许无外网 Wi-Fi 保持连接)
        requestCameraWifiNetwork()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // Wi-Fi 强绑定与网络状态
                "bindCameraWifi" -> {
                    val targetHost = call.argument<String>("targetHost")
                    val res = bindProcessToCameraWifi(targetHost)
                    result.success(res)
                }
                "unbindWifi" -> {
                    unbindProcessWifi()
                    result.success(mapOf("success" to true))
                }
                "getWifiInfo" -> {
                    result.success(getWifiDetails())
                }
                "openWifiSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_WIFI_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INTENT_ERROR", e.localizedMessage, null)
                    }
                }

                // 蓝牙 BLE 操作
                "isBluetoothEnabled" -> {
                    result.success(bluetoothAdapter?.isEnabled == true)
                }
                "openBluetoothSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INTENT_ERROR", e.localizedMessage, null)
                    }
                }
                "startBleScan" -> {
                    startBleScan(result)
                }
                "stopBleScan" -> {
                    stopBleScan()
                    result.success(true)
                }
                "getScannedBleDevices" -> {
                    result.success(scannedDevices.values.toList())
                }
                "connectBleDevice" -> {
                    val address = call.argument<String>("address")
                    if (address.isNullOrBlank()) {
                        result.error("INVALID_ARG", "Device address cannot be empty", null)
                    } else {
                        connectBleDevice(address, result)
                    }
                }
                "disconnectBleDevice" -> {
                    disconnectBleDevice()
                    result.success(true)
                }
                "sendBleShutterCommand" -> {
                    val cmd = call.argument<String>("command") ?: "shutter"
                    val success = sendBleCommand(cmd)
                    result.success(mapOf("success" to success))
                }
                "getBleStatus" -> {
                    result.success(mapOf(
                        "status" to bleStatus,
                        "deviceName" to (bleConnectedDeviceName ?: "")
                    ))
                }
                "getDevicePowerInfo" -> {
                    result.success(getDevicePowerInfo())
                }
                "notifyMediaScan" -> {
                    val path = call.argument<String>("path")
                    if (!path.isNullOrBlank()) {
                        MediaScannerConnection.scanFile(
                            applicationContext,
                            arrayOf(path),
                            null
                        ) { p, uri ->
                            Log.d(TAG, "MediaScanner scanned $p -> $uri")
                        }
                    }
                    result.success(true)
                }
                "pickImage" -> {
                    if (pendingPickResult != null) {
                        result.error("ALREADY_ACTIVE", "Pick operation in progress", null)
                    } else {
                        pendingPickResult = result
                        val intent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
                        intent.type = "image/*"
                        try {
                            startActivityForResult(intent, REQUEST_PICK_IMAGE)
                        } catch (e: Exception) {
                            val fallback = Intent(Intent.ACTION_GET_CONTENT)
                            fallback.type = "image/*"
                            startActivityForResult(fallback, REQUEST_PICK_IMAGE)
                        }
                    }
                }
                "saveImageToGallery" -> {
                    val srcPath = call.argument<String>("srcPath")
                    if (srcPath.isNullOrBlank()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                    } else {
                        val file = File(srcPath)
                        if (!file.exists()) {
                            result.error("NOT_FOUND", "File does not exist", null)
                        } else {
                            mediaTask(result) { saveImageToPublicPictures(file) ?: throw java.io.IOException("MediaStore 保存失败") }
                        }
                    }
                }
                "listSavedMedia" -> mediaTask(result) { listSavedMedia() }
                "materializeMedia" -> {
                    val uri = call.argument<String>("uri")
                    mediaTask(result) { materializeMedia(uri ?: "") }
                }
                "findMediaUris" -> {
                    val fileNames = call.argument<List<*>>("fileNames")?.filterIsInstance<String>() ?: emptyList()
                    result.success(findMediaUrisByNames(fileNames))
                }
                "overwriteMedia" -> {
                    val mediaUri = call.argument<String>("mediaUri")
                    val srcPath = call.argument<String>("srcPath")
                    if (mediaUri.isNullOrBlank() || srcPath.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        mediaTask(result) { overwriteMediaEntry(mediaUri, srcPath) }
                    }
                }
                "deleteMedia" -> {
                    val target = call.argument<String>("target")
                    if (target.isNullOrBlank()) {
                        result.error("INVALID_TARGET", "Target is empty", null)
                    } else {
                        result.success(deleteMediaTarget(target))
                    }
                }
                "saveMediaToGallery" -> {
                    val srcPath = call.argument<String>("srcPath")
                    val fileName = call.argument<String>("fileName")
                    if (srcPath.isNullOrBlank()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                    } else {
                        val file = File(srcPath)
                        if (!file.exists()) {
                            result.error("NOT_FOUND", "File does not exist", null)
                        } else {
                            mediaTask(result) { saveMediaToPublic(file, fileName ?: file.name) ?: throw java.io.IOException("MediaStore 保存失败") }
                        }
                    }
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_PATH", "Path is empty", null)
                    } else {
                        try {
                            val file = File(filePath)
                            if (!file.exists()) {
                                result.error("NOT_FOUND", "File does not exist", null)
                            } else {
                                val apkUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    FileProvider.getUriForFile(
                                        this,
                                        "${applicationContext.packageName}.fileprovider",
                                        file
                                    )
                                } else {
                                    Uri.fromFile(file)
                                }

                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(apkUri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                startActivity(intent)
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to start APK installation", e)
                            result.error("INSTALL_ERROR", e.localizedMessage, null)
                        }
                    }
                }
                "openUrlInBrowser" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("INVALID_URL", "URL is empty", null)
                    } else {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("BROWSER_ERROR", e.localizedMessage, null)
                        }
                    }
                }
                // USB PTP over OTG
                "listUsbDevices" -> result.success(listUsbDevices())
                "requestUsbPermission" -> {
                    val deviceName = call.argument<String>("deviceName")
                    if (deviceName.isNullOrBlank()) {
                        result.error("INVALID_ARG", "deviceName 不能为空", null)
                    } else {
                        requestUsbPermission(deviceName, result)
                    }
                }
                "usbOpenSession" -> {
                    val deviceName = call.argument<String>("deviceName")
                    try {
                        val id = openUsbSession(deviceName)
                        result.success(id)
                    } catch (e: Exception) {
                        result.error("USB_OPEN_FAILED", e.message, null)
                    }
                }
                "usbCloseSession" -> {
                    val deviceId = call.argument<String>("deviceId") ?: pendingUsbPermissionDeviceName
                    closeUsbSession(deviceId)
                    result.success(true)
                }
                "usbQueryDeviceInfo" -> {
                    val deviceId = call.argument<String>("deviceId")
                    try {
                        result.success(queryUsbDeviceInfo(requireUsbSession(deviceId)))
                    } catch (e: Exception) {
                        result.error("USB_QUERY_FAILED", e.message, null)
                    }
                }
                "usbExecuteOperation" -> {
                    val deviceId = call.argument<String>("deviceId")
                    val opCode = call.argument<Int>("opCode") ?: 0
                    val params = intArrayOf(*(call.argument<List<Int>>("params")?.toIntArray() ?: IntArray(0)))
                    try {
                        requireUsbSession(deviceId).executeOperation(opCode, params)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("USB_OPERATION_FAILED", e.message, null)
                    }
                }
                "usbExecuteDataIn" -> {
                    val deviceId = call.argument<String>("deviceId")
                    val opCode = call.argument<Int>("opCode") ?: 0
                    val params = intArrayOf(*(call.argument<List<Int>>("params")?.toIntArray() ?: IntArray(0)))
                    try {
                        result.success(requireUsbSession(deviceId).executeDataIn(opCode, params))
                    } catch (e: Exception) {
                        result.error("USB_DATA_IN_FAILED", e.message, null)
                    }
                }
                "usbExecuteDataOut" -> {
                    val deviceId = call.argument<String>("deviceId")
                    val opCode = call.argument<Int>("opCode") ?: 0
                    val params = intArrayOf(*(call.argument<List<Int>>("params")?.toIntArray() ?: IntArray(0)))
                    val data = call.argument<ByteArray>("data")
                    if (data == null) {
                        result.error("INVALID_ARG", "data 不能为空", null)
                    } else {
                        try {
                            requireUsbSession(deviceId).executeDataOut(opCode, data, params)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("USB_DATA_OUT_FAILED", e.message, null)
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // ==================== USB PTP over OTG ====================

    private fun findUsbDeviceByName(deviceName: String): UsbDevice? =
        usbManager?.deviceList?.values?.firstOrNull { it.deviceName == deviceName }

    /** 枚举已接入的 USB 设备（含尼康厂商识别与授权状态）。 */
    private fun listUsbDevices(): List<Map<String, Any>> {
        val mgr = usbManager ?: return emptyList()
        return mgr.deviceList.values.map { d ->
            val name = try { d.productName } catch (_: Exception) { null }
            mapOf(
                "deviceName" to d.deviceName,
                "vendorId" to d.vendorId,
                "productId" to d.productId,
                "name" to (name ?: "USB Camera"),
                "hasPermission" to mgr.hasPermission(d),
                "isNikon" to (d.vendorId == 0x04B0),
            )
        }
    }

    private fun registerUsbPermissionReceiver() {
        if (usbPermissionReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != ACTION_USB_PERMISSION) return
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                val res = pendingUsbPermissionResult
                pendingUsbPermissionResult = null
                res?.success(granted)
            }
        }
        usbPermissionReceiver = receiver
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    private fun requestUsbPermission(deviceName: String, result: MethodChannel.Result) {
        val mgr = usbManager
        if (mgr == null) {
            result.error("USB_UNAVAILABLE", "UsbManager 不可用", null)
            return
        }
        val device = findUsbDeviceByName(deviceName)
        if (device == null) {
            result.error("USB_NOT_FOUND", "未找到设备: $deviceName", null)
            return
        }
        if (mgr.hasPermission(device)) {
            result.success(true)
            return
        }
        registerUsbPermissionReceiver()
        pendingUsbPermissionDeviceName = deviceName
        pendingUsbPermissionResult = result
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val pi = PendingIntent.getBroadcast(
            this, 0, Intent(ACTION_USB_PERMISSION).setPackage(packageName), flags
        )
        mgr.requestPermission(device, pi)
    }

    /** 选择含 Bulk IN + Bulk OUT 的接口（优先静态图像类）。 */
    private fun selectBulkInterface(device: UsbDevice): Triple<UsbInterface, UsbEndpoint, UsbEndpoint>? {
        val candidates = (0 until device.interfaceCount)
            .map { device.getInterface(it) }
            .sortedByDescending { if (it.interfaceClass == 6) 1 else 0 }
        for (iface in candidates) {
            var epIn: UsbEndpoint? = null
            var epOut: UsbEndpoint? = null
            for (i in 0 until iface.endpointCount) {
                val ep = iface.getEndpoint(i)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                    if (ep.direction == UsbConstants.USB_DIR_IN && epIn == null) epIn = ep
                    if (ep.direction == UsbConstants.USB_DIR_OUT && epOut == null) epOut = ep
                }
            }
            if (epIn != null && epOut != null) return Triple(iface, epIn, epOut)
        }
        return null
    }

    private fun openUsbSession(deviceName: String?): String {
        if (deviceName.isNullOrBlank()) throw IllegalArgumentException("deviceName 不能为空")
        usbSessions.keys.firstOrNull { it.endsWith(":$deviceName") }?.let { return it }
        val mgr = usbManager ?: throw IllegalStateException("UsbManager 不可用")
        val device = findUsbDeviceByName(deviceName) ?: throw IllegalStateException("未找到设备: $deviceName")
        if (!mgr.hasPermission(device)) throw IllegalStateException("缺少 USB 权限，请先授权")
        val connection: UsbDeviceConnection = mgr.openDevice(device)
            ?: throw IllegalStateException("openDevice 失败")
        val selected = selectBulkInterface(device)
        if (selected == null) {
            connection.close()
            throw IllegalStateException("未找到可用的 Bulk IN/OUT 端点")
        }
        val (iface, epIn, epOut) = selected
        val session = UsbPtpSession(device, connection, iface, epIn, epOut)
        try {
            session.open()
            session.executeOperation(0x1002, intArrayOf(1)) // OpenSession
        } catch (e: Exception) {
            session.close()
            throw e
        }
        val id = session.deviceId
        usbSessions[id] = session
        return id
    }

    private fun requireUsbSession(deviceId: String?): UsbPtpSession {
        val id = deviceId ?: usbSessions.keys.firstOrNull()
            ?: throw IllegalStateException("USB 会话未建立")
        return usbSessions[id] ?: throw IllegalStateException("USB 会话不存在: $id")
    }

    private fun closeUsbSession(deviceId: String?) {
        val ids = if (deviceId != null && usbSessions.containsKey(deviceId)) {
            listOf(deviceId)
        } else {
            usbSessions.keys.toList()
        }
        for (id in ids) {
            try {
                usbSessions.remove(id)?.close()
            } catch (_: Exception) {}
        }
    }

    private fun queryUsbDeviceInfo(session: UsbPtpSession): Map<String, Any> {
        val raw = session.executeDataIn(0x1001) // GetDeviceInfo
        return mapOf("raw" to raw)
    }

    private fun getDevicePowerInfo(): Map<String, Any> {
        var level = 100
        var isCharging = false
        var isPowerSaveMode = false

        try {
            val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && bm != null) {
                level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            } else {
                val ifilter = android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                val batteryStatus = registerReceiver(null, ifilter)
                val rawLevel = batteryStatus?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale = batteryStatus?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                if (rawLevel >= 0 && scale > 0) {
                    level = (rawLevel * 100 / scale.toFloat()).toInt()
                }
            }

            val ifilter = android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus = registerReceiver(null, ifilter)
            val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL

            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && pm != null) {
                isPowerSaveMode = pm.isPowerSaveMode
            }
        } catch (e: Exception) {
            Log.e(TAG, "getDevicePowerInfo error: $e")
        }

        return mapOf(
            "level" to level,
            "isCharging" to isCharging,
            "isPowerSaveMode" to isPowerSaveMode
        )
    }


    private fun requestRuntimePermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val list = mutableListOf<String>()
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                list.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES) != PackageManager.PERMISSION_GRANTED) {
                    list.add(Manifest.permission.NEARBY_WIFI_DEVICES)
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                    list.add(Manifest.permission.BLUETOOTH_SCAN)
                }
                if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                    list.add(Manifest.permission.BLUETOOTH_CONNECT)
                }
            }
            if (list.isNotEmpty()) {
                requestPermissions(list.toTypedArray(), 1001)
            }
        }
    }

    /**
     * 注册无外网相机 Wi-Fi 网络请求
     * 对齐原版 CameraSyncForegroundService.java 实现，防止蜂窝数据把无网 Wi-Fi 顶掉
     */
    private fun requestCameraWifiNetwork() {
        if (cameraNetworkCallback != null) return
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()

            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    Log.d(TAG, "[network-bind] requestNetwork onAvailable: $network")
                    boundCameraNetwork = network
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val bound = cm.bindProcessToNetwork(network)
                        Log.d(TAG, "[network-bind] auto bindProcessToNetwork=$bound")
                    }
                }

                override fun onLost(network: Network) {
                    Log.d(TAG, "[network-bind] requestNetwork onLost: $network")
                    if (boundCameraNetwork == network) {
                        boundCameraNetwork = null
                    }
                }
            }
            cameraNetworkCallback = callback
            try {
                cm.requestNetwork(request, callback)
            } catch (e: Exception) {
                Log.e(TAG, "requestNetwork exception: $e")
            }
        }
    }

    /**
     * 将当前 App 进程网络强行绑定到相机 Wi-Fi 接口
     * 针对 targetHost 智能匹配路由网段
     */
    private fun bindProcessToCameraWifi(targetHost: String?): Map<String, Any> {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        var wifiNetwork: Network? = null

        requestCameraWifiNetwork()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val allNetworks = cm.allNetworks
            var candidateWifi: Network? = null

            for (net in allNetworks) {
                val caps = cm.getNetworkCapabilities(net) ?: continue
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                    if (candidateWifi == null) candidateWifi = net

                    if (!targetHost.isNullOrBlank()) {
                        val lp = cm.getLinkProperties(net)
                        if (lp != null) {
                            try {
                                val targetAddr = InetAddress.getByName(targetHost)
                                for (route in lp.routes) {
                                    if (route.matches(targetAddr)) {
                                        wifiNetwork = net
                                        break
                                    }
                                }
                            } catch (_: Exception) {}
                        }
                    }
                }
            }

            if (wifiNetwork == null) {
                wifiNetwork = candidateWifi ?: boundCameraNetwork
            }

            if (wifiNetwork != null) {
                val bound = cm.bindProcessToNetwork(wifiNetwork)
                boundCameraNetwork = wifiNetwork
                Log.d(TAG, "[network-bind] bindProcessToNetwork=$bound for target=$targetHost on $wifiNetwork")
            }
        }

        // 获取并锁定高频 Wi-Fi 性能与 CPU 唤醒锁
        acquireLocks()

        val details = getWifiDetails()
        val res = details.toMutableMap()
        res["bound"] = (wifiNetwork != null)
        return res
    }

    private fun unbindProcessWifi() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.bindProcessToNetwork(null)
            }
            boundCameraNetwork = null
            wifiLock?.let {
                if (it.isHeld) it.release()
            }
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (e: Exception) {
            Log.e(TAG, "unbindProcessWifi error: $e")
        }
    }

    private fun acquireLocks() {
        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (wifiLock == null) {
                @Suppress("DEPRECATION")
                wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "SnapLink:WifiLock")
                wifiLock?.setReferenceCounted(false)
            }
            wifiLock?.acquire()

            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (wakeLock == null) {
                wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SnapLink:WakeLock")
                wakeLock?.setReferenceCounted(false)
            }
            wakeLock?.acquire(3600 * 1000L) // 最长保活 1 小时
        } catch (e: Exception) {
            Log.e(TAG, "acquireLocks error: $e")
        }
    }

    private fun getWifiDetails(): Map<String, Any> {
        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        var isConnected = false
        var ssid = "<unknown>"
        var gatewayIp = "192.168.1.1" // 默认优先匹配用户相机 192.168.1.1 网关
        var localIp = "192.168.1.2"

        try {
            @Suppress("DEPRECATION")
            val wifiInfo = wm.connectionInfo
            if (wifiInfo != null) {
                val currentSsid = wifiInfo.ssid
                if (!currentSsid.isNullOrBlank() && currentSsid != "<unknown ssid>" && currentSsid != "0x") {
                    ssid = currentSsid.replace("\"", "")
                    isConnected = true
                }
                val ipInt = wifiInfo.ipAddress
                if (ipInt != 0) {
                    localIp = formatIpAddress(ipInt)
                    isConnected = true
                }
            }

            @Suppress("DEPRECATION")
            val dhcp = wm.dhcpInfo
            if (dhcp != null && dhcp.gateway != 0) {
                gatewayIp = formatIpAddress(dhcp.gateway)
                isConnected = true
            }

            // Android 10+ 从 LinkProperties 读取路由网关
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                for (net in cm.allNetworks) {
                    val caps = cm.getNetworkCapabilities(net)
                    if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                        isConnected = true
                        val linkProps = cm.getLinkProperties(net)
                        if (linkProps != null) {
                            for (route in linkProps.routes) {
                                if (route.isDefaultRoute && route.gateway != null) {
                                    val gw = route.gateway?.hostAddress
                                    if (!gw.isNullOrBlank() && gw != "0.0.0.0") {
                                        gatewayIp = gw
                                    }
                                }
                            }
                        }
                        break
                    }
                }
            }

            // 如果 SSID 由于系统隐私权限返回 <unknown>，但已检测到相机网卡，友好显示机型网段
            if (ssid == "<unknown>" && isConnected) {
                ssid = "相机 Wi-Fi (${gatewayIp.substringBeforeLast(".")}.x)"
            }
        } catch (e: Exception) {
            Log.e(TAG, "getWifiDetails error: $e")
        }

        return mapOf(
            "connected" to isConnected,
            "ssid" to ssid,
            "gateway" to gatewayIp,
            "ip" to localIp
        )
    }

    private fun formatIpAddress(ip: Int): String {
        return String.format(
            "%d.%d.%d.%d",
            ip and 0xff,
            (ip shr 8) and 0xff,
            (ip shr 16) and 0xff,
            (ip shr 24) and 0xff
        )
    }

    // ==========================================
    // 蓝牙 BLE 扫描与快门控制
    // ==========================================
    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult?) {
            result?.device?.let { device ->
                val name = try { device.name } catch (e: SecurityException) { null } ?: "未知设备"
                val address = device.address
                val rssi = result.rssi
                val isNikon = name.startsWith("NIKON", true) ||
                        name.startsWith("Nikon", true) ||
                        name.contains("Z ", true) ||
                        name.contains("Z6", true) ||
                        name.contains("Z7", true) ||
                        name.contains("Z5", true) ||
                        name.contains("Z8", true) ||
                        name.contains("Z9", true) ||
                        name.contains("Z50", true) ||
                        name.contains("Z30", true) ||
                        name.contains("Zfc", true) ||
                        name.contains("D850", true) ||
                        name.contains("D780", true) ||
                        name.contains("D7500", true) ||
                        name.contains("D5600", true) ||
                        name.contains("ML-L7", true) ||
                        name.contains("Camera", true)

                scannedDevices[address] = mapOf(
                    "name" to name,
                    "address" to address,
                    "rssi" to rssi,
                    "isNikon" to isNikon
                )
            }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "BLE Scan failed: $errorCode")
            isScanning = false
        }
    }

    private fun startBleScan(result: MethodChannel.Result) {
        val scanner = bluetoothAdapter?.bluetoothLeScanner
        if (scanner == null) {
            result.error("NO_SCANNER", "Bluetooth LE Scanner 不可用或未开启蓝牙", null)
            return
        }
        scannedDevices.clear()
        try {
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            scanner.startScan(null, settings, scanCallback)
            isScanning = true
            result.success(true)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "缺少蓝牙扫描权限: ${e.message}", null)
        } catch (e: Exception) {
            result.error("SCAN_ERROR", e.message, null)
        }
    }

    private fun stopBleScan() {
        if (isScanning) {
            try {
                bluetoothAdapter?.bluetoothLeScanner?.stopScan(scanCallback)
            } catch (e: Exception) {
                Log.e(TAG, "stopBleScan error: $e")
            }
            isScanning = false
        }
    }

    private fun connectBleDevice(address: String, result: MethodChannel.Result) {
        stopBleScan()
        val device = try {
            bluetoothAdapter?.getRemoteDevice(address)
        } catch (e: Exception) {
            result.error("DEVICE_NOT_FOUND", e.message, null)
            return
        }

        if (device == null) {
            result.error("DEVICE_NOT_FOUND", "设备不存在: $address", null)
            return
        }

        bleStatus = "connecting"
        bleConnectedDeviceName = try { device.name } catch (e: SecurityException) { null } ?: address

        try {
            activeGatt?.close()
            activeGatt = device.connectGatt(this, false, object : BluetoothGattCallback() {
                override fun onConnectionStateChange(gatt: BluetoothGatt?, status: Int, newState: Int) {
                    if (newState == BluetoothProfile.STATE_CONNECTED) {
                        bleStatus = "connected"
                        Log.d(TAG, "BLE 已连接，发现服务...")
                        try {
                            gatt?.discoverServices()
                        } catch (e: SecurityException) {
                            Log.e(TAG, "discoverServices SecurityException: $e")
                        }
                    } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                        bleStatus = "disconnected"
                        bleConnectedDeviceName = null
                        Log.d(TAG, "BLE 已断开连接")
                    }
                }

                override fun onServicesDiscovered(gatt: BluetoothGatt?, status: Int) {
                    Log.d(TAG, "BLE 服务发现完成: status=$status, count=${gatt?.services?.size}")
                }
            }, BluetoothDevice.TRANSPORT_LE)

            result.success(mapOf("status" to "connecting", "name" to bleConnectedDeviceName))
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", "缺少蓝牙连接权限: ${e.message}", null)
        } catch (e: Exception) {
            result.error("CONNECT_ERROR", e.message, null)
        }
    }

    private fun disconnectBleDevice() {
        try {
            activeGatt?.disconnect()
            activeGatt?.close()
            activeGatt = null
            bleStatus = "disconnected"
            bleConnectedDeviceName = null
        } catch (e: Exception) {
            Log.e(TAG, "disconnectBleDevice error: $e")
        }
    }

    private fun sendBleCommand(command: String): Boolean {
        val gatt = activeGatt ?: return false
        for (service in gatt.services) {
            for (ch in service.characteristics) {
                val props = ch.properties
                if ((props and BluetoothGattCharacteristic.PROPERTY_WRITE != 0) ||
                    (props and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0)) {
                    val data = when (command) {
                        "half_press" -> byteArrayOf(0x01)
                        "shutter" -> byteArrayOf(0x02)
                        "record_video" -> byteArrayOf(0x03)
                        else -> byteArrayOf(0x00)
                    }
                    @Suppress("DEPRECATION")
                    ch.value = data
                    try {
                        @Suppress("DEPRECATION")
                        gatt.writeCharacteristic(ch)
                        return true
                    } catch (e: SecurityException) {
                        return false
                    }
                }
            }
        }
        return true
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK_IMAGE) {
            val res = pendingPickResult
            pendingPickResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                try {
                    val inputStream = contentResolver.openInputStream(uri)
                    val tempFile = File(cacheDir, "picked_photo_${System.currentTimeMillis()}.jpg")
                    val outputStream = FileOutputStream(tempFile)
                    inputStream?.copyTo(outputStream)
                    inputStream?.close()
                    outputStream.close()
                    res?.success(tempFile.absolutePath)
                } catch (e: Exception) {
                    res?.error("PICK_ERROR", e.localizedMessage, null)
                }
            } else {
                res?.success(null)
            }
        }
    }

    /**
     * 用本地文件字节覆盖已有 MediaStore 条目的内容。
     * 仅对本应用写入的条目可靠；异常或 0 字节写入返回 false，由 Dart 回退到另存。
     */
    private fun mediaTask(result: MethodChannel.Result, work: () -> Any?) {
        mediaExecutor.execute {
            try {
                val value = work()
                runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                val code = if (e is IllegalStateException) "OVERWRITE_RESTORE_FAILED" else "MEDIA_READ_FAILED"
                runOnUiThread { result.error(code, e.message, null) }
            }
        }
    }

    private fun listSavedMedia(): List<Map<String, Any>> {
        val collection = MediaStore.Files.getContentUri("external")
        val pathColumn = if (Build.VERSION.SDK_INT >= 29) MediaStore.MediaColumns.RELATIVE_PATH else MediaStore.MediaColumns.DATA
        val columns = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.DATE_MODIFIED, pathColumn)
        val found = mutableListOf<Map<String, Any>>()
        val selection = "$pathColumn LIKE ? OR $pathColumn LIKE ?"
        contentResolver.query(collection, columns, selection, arrayOf("%/SnapLink/%", "SnapLink/%"), null)?.use { c ->
            while (c.moveToNext()) {
                val path = c.getString(4) ?: continue
                if (!path.replace('\\', '/').split('/').any { it.equals("SnapLink", true) }) continue
                val name = c.getString(1) ?: continue
                if (!Regex("(?i).*\\.(jpg|jpeg|png|nef|nrw|mov|mp4)$").matches(name)) continue
                val uri = if (Build.VERSION.SDK_INT < 29) path else
                    Uri.withAppendedPath(resolveSaveTarget(name).first, c.getLong(0).toString()).toString()
                found.add(mapOf("uri" to uri,
                    "name" to name, "size" to c.getLong(2), "modified" to c.getLong(3) * 1000L,
                    "path" to if (Build.VERSION.SDK_INT < 29) path else ""))
            }
        }
        return found
    }

    private fun materializeMedia(target: String): String? {
        val uri = Uri.parse(target)
        require(uri.scheme == "content" && uri.authority == "media") { "无效的媒体 URI" }
        val dir = File(cacheDir, "saved_media").apply { mkdirs() }
        val digest = MessageDigest.getInstance("SHA-256").digest(target.toByteArray()).joinToString("") { "%02x".format(it) }
        var size = 0L
        var modified = 0L
        var name = "image.jpg"
        contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.SIZE, MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (!c.moveToFirst()) return null
            size = c.getLong(0); modified = c.getLong(1); name = c.getString(2) ?: name
        } ?: return null
        val ext = name.substringAfterLast('.', "jpg").lowercase().filter { it.isLetterOrDigit() }
        val dest = File(dir, "${digest}_${modified}_${size}.$ext")
        if (dest.exists() && dest.length() == size && size > 0) {
            dest.setLastModified(System.currentTimeMillis())
            return dest.absolutePath
        }
        val partial = File(dir, dest.name + ".part")
        try {
            contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(partial).use { input.copyTo(it) } } ?: return null
            if (partial.length() != size || size == 0L) throw java.io.IOException("本地媒体长度不完整")
            if (!partial.renameTo(dest)) throw java.io.IOException("本地缓存保存失败")
            // 仅删除此 URI 的旧缓存；其他照片由应用缓存生命周期管理。
            dir.listFiles()?.filter { it.name.startsWith(digest + "_") && it != dest }?.forEach { it.delete() }
            // 缓存上限 128MiB，单张更大的当前照片保留；严格限额需改为流式读取。
            val cached = dir.listFiles()?.filter { it.isFile }?.sortedBy { it.lastModified() } ?: emptyList()
            var total = cached.sumOf { it.length() }
            for (file in cached) {
                if (total <= 128L * 1024 * 1024) break
                if (file == dest) continue
                val length = file.length()
                if (file.delete()) total -= length
            }
            return dest.absolutePath
        } finally { partial.delete() }
    }

    private fun mediaMatchesFile(uri: Uri, file: File): Boolean {
        fun digest(input: java.io.InputStream): ByteArray {
            val hash = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(64 * 1024)
            while (true) { val n = input.read(buffer); if (n < 0) break; hash.update(buffer, 0, n) }
            return hash.digest()
        }
        val expected = FileInputStream(file).use { digest(it) }
        val actual = contentResolver.openInputStream(uri)?.use { digest(it) } ?: return false
        return expected.contentEquals(actual)
    }

    private fun overwriteMediaEntry(mediaUri: String, srcPath: String): Boolean {
        val srcFile = File(srcPath)
        if (!srcFile.exists() || srcFile.length() == 0L) return false
        val uri = Uri.parse(mediaUri)
        if (uri.scheme != "content" || uri.authority != "media") return false
        if (Build.VERSION.SDK_INT >= 29) {
            contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.OWNER_PACKAGE_NAME), null, null, null)?.use { c ->
                if (!c.moveToFirst() || c.getString(0) != packageName) return false
            } ?: return false
        }
        var keepBackup = false
        val backupDir = File(filesDir, "photo_backups").apply { mkdirs() }
        val backup = File.createTempFile("snaplink_original_", ".bak", backupDir)
        try {
            contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(backup).use { input.copyTo(it) } } ?: return false
            try {
                contentResolver.openOutputStream(uri, "wt")?.use { out -> FileInputStream(srcFile).use { it.copyTo(out) } }
                    ?: return false
                if (!mediaMatchesFile(uri, srcFile)) throw java.io.IOException("覆盖校验失败")
                val values = ContentValues().apply { put(MediaStore.MediaColumns.DATE_MODIFIED, System.currentTimeMillis() / 1000) }
                contentResolver.update(uri, values, null, null)
                val digest = MessageDigest.getInstance("SHA-256").digest(mediaUri.toByteArray()).joinToString("") { "%02x".format(it) }
                File(cacheDir, "saved_media").listFiles()?.filter { it.name.startsWith(digest + "_") }?.forEach { it.delete() }
                return true
            } catch (writeError: Exception) {
                try {
                    contentResolver.openOutputStream(uri, "wt")?.use { out -> FileInputStream(backup).use { it.copyTo(out) } }
                        ?: throw java.io.IOException("无法恢复原图")
                    if (!mediaMatchesFile(uri, backup)) throw java.io.IOException("原图恢复校验失败")
                } catch (restoreError: Exception) {
                    // 恢复失败时保留备份，供用户恢复；绝不能静默另存后报告成功。
                    keepBackup = true
                    throw IllegalStateException("原图恢复失败；备份位于 " + backup.absolutePath, restoreError)
                }
                return false
            }
        } catch (e: IllegalStateException) { throw e
        } catch (e: Exception) { Log.e(TAG, "overwrite failed", e); return false
        } finally { if (!keepBackup) backup.delete() }
    }

    /**
     * 批量按文件名反查 MediaStore URI。
     * 每个媒体集合只查询一次，返回 fileName -> URI；只接受 SnapLink 目录，避免误删同名系统文件。
     */
    private fun findMediaUrisByNames(fileNames: List<String>): Map<String, String> {
        if (fileNames.isEmpty()) return emptyMap()
        val wanted = fileNames.toSet()
        val result = mutableMapOf<String, String>()
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.RELATIVE_PATH
        )
        val collections = listOf(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Files.getContentUri("external")
        )
        for (collection in collections) {
            try {
                contentResolver.query(collection, projection, null, null, null)?.use { cursor ->
                    val idIdx = cursor.getColumnIndex(MediaStore.MediaColumns._ID)
                    val nameIdx = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                    val relIdx = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                    while (cursor.moveToNext()) {
                        if (idIdx < 0 || nameIdx < 0) continue
                        val name = cursor.getString(nameIdx) ?: continue
                        if (name !in wanted || result.containsKey(name)) continue
                        val relative = if (relIdx >= 0) cursor.getString(relIdx) else null
                        if (relative != null && !relative.contains("SnapLink", ignoreCase = true)) continue
                        result[name] = Uri.withAppendedPath(collection, cursor.getLong(idIdx).toString()).toString()
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "findMediaUrisByNames failed: " + e.message)
            }
        }
        return result
    }

    /**
     * 删除公共媒体库条目（content:// URI，Android 10+ 无需存储权限）或旧系统绝对路径文件。
     * 返回 true 表示条目/文件已不存在或删除成功。
     */
    private fun deleteMediaTarget(target: String): Boolean {
        return try {
            if (target.startsWith("content://")) {
                val uri = Uri.parse(target)
                val deleted = contentResolver.delete(uri, null, null)
                deleted > 0
            } else {
                val file = File(target)
                if (file.exists()) file.delete() else true
            }
        } catch (e: Exception) {
            Log.e(TAG, "deleteMediaTarget failed: " + e.message)
            false
        }
    }

    /** 按媒体类型选择公共集合：图片 -> Pictures/SnapLink，视频 -> Movies/SnapLink，RAW -> Downloads/SnapLink */
    private fun resolveSaveTarget(fileName: String): Triple<Uri, String, String?> {
        val lower = fileName.lowercase()
        val mime = when {
            lower.endsWith(".png") -> "image/png"
            lower.endsWith(".nef") || lower.endsWith(".nrw") -> "image/x-nikon-nef"
            lower.endsWith(".mp4") -> "video/mp4"
            lower.endsWith(".mov") -> "video/quicktime"
            else -> "image/jpeg"
        }
        val isVideo = lower.endsWith(".mp4") || lower.endsWith(".mov")
        val isRaw = lower.endsWith(".nef") || lower.endsWith(".nrw")
        return when {
            isVideo -> Triple(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, "Movies/SnapLink", mime)
            isRaw -> Triple(MediaStore.Files.getContentUri("external"), "Download/SnapLink", mime)
            else -> Triple(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "Pictures/SnapLink", mime)
        }
    }

    private fun mimeForFileName(fileName: String): String = resolveSaveTarget(fileName).third ?: "image/jpeg"

    /** 按调用方给定的文件名（可覆盖临时 .part 名）保存到公共媒体库。 */
    private fun saveMediaToPublic(srcFile: File, fileName: String): String? {
        return saveMediaToPublicInternal(srcFile, fileName)
    }

    /**
     * 将应用私有文件保存进系统公共媒体库（Android 10+ 走 MediaStore，无需存储权限）。
     * 返回公共 MediaStore Uri 字符串；失败返回 null，由调用方标记任务失败。
     */
    private fun saveImageToPublicPictures(srcFile: File): String? =
        saveMediaToPublicInternal(srcFile, srcFile.name)

    private fun saveMediaToPublicInternal(srcFile: File, fileName: String): String? {
        val (collection, relativePath, mime) = resolveSaveTarget(fileName)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime ?: "application/octet-stream")
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(collection, values)
                    ?: return null
                try {
                    contentResolver.openOutputStream(uri)?.use { out ->
                        FileInputStream(srcFile).use { input -> input.copyTo(out) }
                    } ?: run {
                        contentResolver.delete(uri, null, null)
                        return null
                    }
                    values.clear()
                    values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                    return uri.toString()
                } catch (e: Exception) {
                    contentResolver.delete(uri, null, null)
                    throw e
                }
            } else {
                val targetDir = File(
                    if (collection == MediaStore.Video.Media.EXTERNAL_CONTENT_URI) {
                        "/storage/emulated/0/Movies/SnapLink"
                    } else if (collection == MediaStore.Files.getContentUri("external")) {
                        "/storage/emulated/0/Download/SnapLink"
                    } else {
                        "/storage/emulated/0/Pictures/SnapLink"
                    }
                )
                if (!targetDir.exists()) targetDir.mkdirs()
                val targetFile = File(targetDir, fileName)
                FileInputStream(srcFile).use { input ->
                    FileOutputStream(targetFile).use { output -> input.copyTo(output) }
                }
                MediaScannerConnection.scanFile(applicationContext, arrayOf(targetFile.absolutePath), null, null)
                return targetFile.absolutePath
            }
        } catch (e: Exception) {
            Log.e(TAG, "saveImageToPublicPictures failed: ${e.message}")
        }
        return null
    }

    override fun onDestroy() {
        mediaExecutor.shutdown()
        super.onDestroy()
        if (cameraNetworkCallback != null) {
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.unregisterNetworkCallback(cameraNetworkCallback!!)
            } catch (_: Exception) {}
        }
        unbindProcessWifi()
        disconnectBleDevice()
        closeUsbSession(null)
        try {
            usbPermissionReceiver?.let { unregisterReceiver(it) }
        } catch (_: Exception) {}
        usbPermissionReceiver = null
    }
}
