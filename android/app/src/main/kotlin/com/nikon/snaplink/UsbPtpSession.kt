package com.nikon.snaplink

import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * PTP over USB (Bulk-Only) 会话实现。
 *
 * 移植自 reverse_analysis/jadx_output/sources/p086T1/C1117j1.java：
 * 统一的 PTP 容器布局为 [长度 4B][类型 2B][操作码/保留 2B][事务ID 4B][参数或数据 N B]（均为小端）。
 *   - 命令容器 Type = 1（操作码 + 参数）
 *   - 数据容器 Type = 2（仅数据阶段，第 3、4 字段保留/事务 ID）
 *   - 响应容器 Type = 3（操作码字段承载响应码，第 4 字段为事务 ID）
 * 仅依赖 Android USB Host API，不引用任何闭源库。
 */
class UsbPtpSession(
    private val device: UsbDevice,
    private val connection: UsbDeviceConnection,
    private val iface: UsbInterface,
    private val epIn: UsbEndpoint,
    private val epOut: UsbEndpoint,
) {
    private companion object {
        const val RESPONSE_OK = 0x2001
        const val RESPONSE_SESSION_ALREADY_OPEN = 0x201E
        const val TYPE_COMMAND = 1
        const val TYPE_DATA = 2
        const val TYPE_RESPONSE = 3
        const val IO_TIMEOUT_MS = 6000
    }

    private val txCounter = AtomicInteger(0)
    private val closed = AtomicBoolean(false)
    private var buffered = ByteArray(0)
    private var bufferedOffset = 0

    fun open() {
        if (!connection.claimInterface(iface, true)) {
            throw IllegalStateException("无法 claim USB 接口 ${iface.id}")
        }
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        runCatching { executeOperation(0x1003) } // CloseSession
        runCatching { connection.releaseInterface(iface) }
        runCatching { connection.close() }
    }

    // ---------------- 公开 PTP 操作 ----------------

    /** 无数据阶段指令：读响应容器并校验成功。 */
    fun executeOperation(opCode: Int, params: IntArray = IntArray(0)) {
        val tx = txCounter.incrementAndGet()
        sendCommandContainer(opCode, tx, params)
        val header = readHeader()
        requireType(header.type, TYPE_RESPONSE, opCode)
        skipPayload(header.length)
        checkResponse(opCode, header.code)
    }

    /** 数据输入：返回相机发来的数据阶段负载。 */
    fun executeDataIn(opCode: Int, params: IntArray = IntArray(0)): ByteArray {
        val tx = txCounter.incrementAndGet()
        sendCommandContainer(opCode, tx, params)

        val dataHeader = readHeader()
        requireType(dataHeader.type, TYPE_DATA, opCode)
        val payloadLen = dataHeader.length - 12
        val out = ByteArrayOutputStream(if (payloadLen > 0) payloadLen else 0)
        if (payloadLen > 0) readIntoBuffer(out, payloadLen.toLong())

        val respHeader = readHeader()
        requireType(respHeader.type, TYPE_RESPONSE, opCode)
        skipPayload(respHeader.length)
        checkResponse(opCode, respHeader.code)
        return out.toByteArray()
    }

    /** 数据输出：把 [data] 作为数据阶段发送。 */
    fun executeDataOut(opCode: Int, data: ByteArray, params: IntArray = IntArray(0)) {
        val tx = txCounter.incrementAndGet()
        sendCommandContainer(opCode, tx, params)
        sendDataContainer(tx, data)
        val header = readHeader()
        requireType(header.type, TYPE_RESPONSE, opCode)
        skipPayload(header.length)
        checkResponse(opCode, header.code)
    }

    // ---------------- 容器编解码 ----------------

    private class Header(val length: Int, val type: Int, val code: Int)

    private fun sendCommandContainer(opCode: Int, tx: Int, params: IntArray) {
        val len = 12 + params.size * 4
        val b = ByteBuffer.allocate(len).order(ByteOrder.LITTLE_ENDIAN)
        b.putInt(len)
        b.putShort(TYPE_COMMAND.toShort())
        b.putShort(opCode.toShort())
        b.putInt(tx)
        for (p in params) b.putInt(p)
        writeAll(b.array())
    }

    private fun sendDataContainer(tx: Int, data: ByteArray) {
        val len = 12 + data.size
        val b = ByteBuffer.allocate(len).order(ByteOrder.LITTLE_ENDIAN)
        b.putInt(len)
        b.putShort(TYPE_DATA.toShort())
        b.putShort(0)
        b.putInt(tx)
        b.put(data)
        writeAll(b.array())
    }

    /** 仅读取 12 字节容器头，负载由调用方按 length 消费。 */
    private fun readHeader(): Header {
        val header = readExact(12)
        val b = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
        val length = b.int
        val type = b.short.toInt() and 0xFFFF
        val code = b.short.toInt() and 0xFFFF
        b.int // 事务 ID（无需用于校验）
        if (length < 12) throw IllegalStateException("PTP 容器长度非法: $length")
        return Header(length, type, code)
    }

    private fun skipPayload(containerLength: Int) = skipBytes((containerLength - 12).toLong())

    private fun requireType(actual: Int, expected: Int, opCode: Int) {
        if (actual != expected) {
            throw IllegalStateException("操作 0x${opCode.toString(16)} 容器类型异常: $actual（期望 $expected）")
        }
    }

    private fun checkResponse(opCode: Int, code: Int) {
        if (code == RESPONSE_OK) return
        if (opCode == 0x1002 && code == RESPONSE_SESSION_ALREADY_OPEN) return
        throw PtpUsbException(opCode, code)
    }

    // ---------------- 裸字节 IO ----------------

    private fun readExact(count: Int): ByteArray {
        val out = ByteArray(count)
        var filled = 0
        while (filled < count) {
            val n = readChunk(out, filled, count - filled)
            if (n <= 0) throw IllegalStateException("USB 读取失败: $n")
            filled += n
        }
        return out
    }

    private fun readIntoBuffer(out: ByteArrayOutputStream, count: Long) {
        var remaining = count
        while (remaining > 0) {
            val tmp = ByteArray(minOf(65536L, remaining).toInt())
            val n = readChunk(tmp, 0, tmp.size)
            if (n <= 0) throw IllegalStateException("USB 读取失败: $n")
            out.write(tmp, 0, n)
            remaining -= n
        }
    }

    /** 优先消费内部缓冲，再从 Bulk IN 端点读取；返回实际写入 dst 的字节数。 */
    private fun readChunk(dst: ByteArray, offset: Int, length: Int): Int {
        val available = buffered.size - bufferedOffset
        if (available > 0) {
            val n = minOf(length, available)
            System.arraycopy(buffered, bufferedOffset, dst, offset, n)
            bufferedOffset += n
            if (bufferedOffset >= buffered.size) {
                buffered = ByteArray(0)
                bufferedOffset = 0
            }
            return n
        }
        val tmp = ByteArray(maxOf(length, 65536))
        val n = connection.bulkTransfer(epIn, tmp, tmp.size, IO_TIMEOUT_MS)
        if (n <= 0) return n
        val copy = minOf(n, length)
        System.arraycopy(tmp, 0, dst, offset, copy)
        if (n > copy) {
            buffered = tmp
            bufferedOffset = copy
        }
        return copy
    }

    private fun skipBytes(count: Long) {
        var remaining = count
        val sink = ByteArray(8192)
        while (remaining > 0) {
            val want = minOf(8192L, remaining).toInt()
            val n = readChunk(sink, 0, want)
            if (n <= 0) throw IllegalStateException("USB 跳过数据失败: $n")
            remaining -= n
        }
    }

    private fun writeAll(data: ByteArray) {
        var offset = 0
        while (offset < data.size) {
            val n = connection.bulkTransfer(epOut, data, offset, data.size - offset, IO_TIMEOUT_MS)
            if (n <= 0) throw IllegalStateException("USB 写入失败: $n")
            offset += n
        }
    }

    val deviceId: String
        get() = "usb:${device.vendorId}:${device.productId}:${device.deviceName}"
}

/** PTP over USB 响应码异常。 */
class PtpUsbException(val opCode: Int, val responseCode: Int) :
    Exception("PTP USB 操作 0x${opCode.toString(16)} 失败，响应码 0x${responseCode.toString(16)}")
