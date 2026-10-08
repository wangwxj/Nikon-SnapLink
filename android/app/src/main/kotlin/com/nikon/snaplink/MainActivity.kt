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
import androidx.core.content.FileProvider

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.nikon.snaplink/native_camera"
    private val TAG = "SnapLinkNative"
    private val REQUEST_PICK_IMAGE = 1001
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bm?.adapter

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
                            val saved = saveImageToPublicPictures(file)
                            result.success(saved)
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
                else -> {
                    result.notImplemented()
                }
            }
        }
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

    private fun saveImageToPublicPictures(srcFile: File): String {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, srcFile.name)
                    put(MediaStore.Images.Media.MIME_TYPE, if (srcFile.name.endsWith(".png", true)) "image/png" else "image/jpeg")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/SnapLink")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                if (uri != null) {
                    contentResolver.openOutputStream(uri)?.use { out ->
                        FileInputStream(srcFile).use { input ->
                            input.copyTo(out)
                        }
                    }
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                    return uri.toString()
                }
            } else {
                val targetDir = File("/storage/emulated/0/Pictures/SnapLink")
                if (!targetDir.exists()) targetDir.mkdirs()
                val targetFile = File(targetDir, srcFile.name)
                FileInputStream(srcFile).use { input ->
                    FileOutputStream(targetFile).use { output ->
                        input.copyTo(output)
                    }
                }
                MediaScannerConnection.scanFile(applicationContext, arrayOf(targetFile.absolutePath), null, null)
                return targetFile.absolutePath
            }
        } catch (e: Exception) {
            Log.e(TAG, "saveImageToPublicPictures failed: ${e.message}")
        }
        return srcFile.absolutePath
    }

    override fun onDestroy() {
        super.onDestroy()
        if (cameraNetworkCallback != null) {
            try {
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                cm.unregisterNetworkCallback(cameraNetworkCallback!!)
            } catch (_: Exception) {}
        }
        unbindProcessWifi()
        disconnectBleDevice()
    }
}
