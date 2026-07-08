package com.madar.madar

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Native Bluetooth Classic (SPP / RFCOMM) bridge for thermal receipt printers.
 *
 * Why this exists instead of the `print_bluetooth_thermal` plugin: that plugin
 * opens ONLY a *secure* RFCOMM socket (`createRfcommSocketToServiceRecord`) with
 * no fallback. Cheap portable printers (e.g. the Xprinter P300) reject the secure
 * socket and connect only over the INSECURE socket or the reflection channel-1
 * hack — the very fallbacks RawBT uses. Trying all three is the whole reason
 * printing failed in-app yet worked in RawBT.
 *
 * It also filters the bonded-device list to actual printers by Class-of-Device,
 * so Settings lists printers instead of every paired phone / earbud / watch.
 *
 * All socket I/O runs on a single background thread; results are posted back on
 * the main thread (Flutter requires MethodChannel replies on the platform thread).
 */
class BtPrinter {
    companion object {
        const val CHANNEL = "com.madar.madar/bt_printer"

        /** Serial Port Profile — the RFCOMM service every ESC/POS printer exposes. */
        private val SPP_UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

        /** Substrings that mark a device as a printer regardless of its declared
         *  Class-of-Device (many cheap heads report UNCATEGORIZED). Lowercased. */
        private val NAME_HINTS = listOf(
            "print", "pos", "receipt", "thermal", "xprinter", "xp-", "p300",
            "p323", "rpp", "mpt", "mtp", "ppt", "spp-r", "bixolon", "gprinter",
            "goojprt", "zjiang", "sunmi", "btp", "znt", "escpos", "esc/pos"
        )
    }

    private val adapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var socket: BluetoothSocket? = null
    private var out: OutputStream? = null
    private var connectedAddress: String? = null

    /** Dispatch a MethodChannel call. Pure lookups reply inline; I/O goes async. */
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isEnabled" -> result.success(adapter?.isEnabled == true)
            "isConnected" -> result.success(isConnected())
            "pairedPrinters" -> onIo(result) { pairedPrinters() }
            "connect" -> {
                val address = call.argument<String>("address")
                if (address == null) {
                    result.error("arg", "address required", null)
                } else {
                    onIo(result) { connect(address) }
                }
            }
            "write" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val chunk = call.argument<Int>("chunkSize") ?: 512
                val throttle = call.argument<Int>("throttleMs") ?: 0
                if (bytes == null) {
                    result.error("arg", "bytes required", null)
                } else {
                    onIo(result) { write(bytes, chunk, throttle) }
                }
            }
            "disconnect" -> onIo(result) { disconnect(); true }
            else -> result.notImplemented()
        }
    }

    /** Run [work] on the I/O thread; deliver its value (or error) on the main thread. */
    private fun <T> onIo(result: MethodChannel.Result, work: () -> T) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                val msg = e.message
                main.post { result.error("bt_error", msg, null) }
            }
        }
    }

    // ── discovery ────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun pairedPrinters(): List<Map<String, Any?>> {
        val bonded = try {
            adapter?.bondedDevices ?: emptySet()
        } catch (e: SecurityException) {
            emptySet()
        }
        return bonded
            .filter { isLikelyPrinter(it) }
            .map { mapOf("name" to (safeName(it) ?: it.address), "address" to it.address) }
    }

    /**
     * Keep printers, drop obvious non-printers. A printer usually reports the
     * IMAGING major class (with the printer minor bit), but plenty of cheap heads
     * report UNCATEGORIZED / MISC — so we INCLUDE those (and name matches) and only
     * EXCLUDE clearly-not-a-printer major classes. Better to show one stray device
     * than to hide the user's actual printer.
     */
    @SuppressLint("MissingPermission")
    private fun isLikelyPrinter(d: BluetoothDevice): Boolean {
        if (nameLooksLikePrinter(safeName(d) ?: "")) return true
        val major = try {
            d.bluetoothClass?.majorDeviceClass
        } catch (e: SecurityException) {
            null
        } ?: return true // class unreadable → don't hide it
        return when (major) {
            BluetoothClass.Device.Major.IMAGING,
            BluetoothClass.Device.Major.MISC,
            BluetoothClass.Device.Major.UNCATEGORIZED -> true
            // phone, computer, audio_video, wearable, health, toy, networking, peripheral
            else -> false
        }
    }

    private fun nameLooksLikePrinter(name: String): Boolean {
        val n = name.lowercase()
        return NAME_HINTS.any { n.contains(it) }
    }

    @SuppressLint("MissingPermission")
    private fun safeName(d: BluetoothDevice): String? =
        try { d.name } catch (e: SecurityException) { null }

    // ── connection (secure → insecure → reflection, à la RawBT) ───────────────

    @SuppressLint("MissingPermission")
    private fun connect(address: String): Boolean {
        if (isConnected() && connectedAddress == address) return true
        disconnect()
        val device = adapter?.getRemoteDevice(address) ?: return false
        try {
            adapter.cancelDiscovery()
        } catch (e: SecurityException) {
        }
        val opened = openSecure(device) ?: openInsecure(device) ?: openReflection(device) ?: return false
        socket = opened
        out = opened.outputStream
        connectedAddress = address
        return true
    }

    @SuppressLint("MissingPermission")
    private fun openSecure(d: BluetoothDevice): BluetoothSocket? =
        tryOpen { d.createRfcommSocketToServiceRecord(SPP_UUID) }

    @SuppressLint("MissingPermission")
    private fun openInsecure(d: BluetoothDevice): BluetoothSocket? =
        tryOpen { d.createInsecureRfcommSocketToServiceRecord(SPP_UUID) }

    /** Last-resort hidden-API channel-1 socket — some clones only accept this. */
    private fun openReflection(d: BluetoothDevice): BluetoothSocket? =
        tryOpen {
            val m = d.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
            m.invoke(d, 1) as BluetoothSocket
        }

    private fun tryOpen(make: () -> BluetoothSocket): BluetoothSocket? {
        var s: BluetoothSocket? = null
        return try {
            s = make()
            s.connect()
            if (s.isConnected) s else { s.close(); null }
        } catch (e: Exception) {
            try { s?.close() } catch (_: Exception) {}
            null
        }
    }

    // ── writing / teardown ────────────────────────────────────────────────────

    /** Write [bytes] in [chunkSize] slices, pausing [throttleMs] between them so a
     *  small-buffer portable head can drain a large Arabic raster. */
    private fun write(bytes: ByteArray, chunkSize: Int, throttleMs: Int): Boolean {
        val stream = out ?: return false
        val step = if (chunkSize > 0) chunkSize else bytes.size.coerceAtLeast(1)
        var off = 0
        while (off < bytes.size) {
            val end = minOf(off + step, bytes.size)
            stream.write(bytes, off, end - off)
            stream.flush()
            off = end
            if (throttleMs > 0 && off < bytes.size) Thread.sleep(throttleMs.toLong())
        }
        return true
    }

    private fun isConnected(): Boolean = socket?.isConnected == true

    private fun disconnect() {
        try { out?.flush() } catch (_: Exception) {}
        try { socket?.close() } catch (_: Exception) {}
        out = null
        socket = null
        connectedAddress = null
    }
}
