
package com.example.disaster_mesh

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelUuid
import android.util.Log
import org.json.JSONObject
import java.util.UUID

/**
 * Keeps DisasterMesh BLE advertising and its GATT server alive
 * while the application is in the background.
 */
class DisasterMeshBleService : Service() {

    companion object {
        private const val TAG = "DisasterMeshService"

        private const val SERVICE_NOTIFICATION_ID = 1001
        private const val MESSAGE_NOTIFICATION_CHANNEL =
            "disaster_mesh_messages"
        private const val CONNECTION_NOTIFICATION_CHANNEL =
            "disaster_mesh_connections"
        private const val SERVICE_NOTIFICATION_CHANNEL =
            "disaster_mesh_service"

        const val ACTION_START =
            "com.example.disaster_mesh.START"
        const val ACTION_STOP =
            "com.example.disaster_mesh.STOP"
        const val ACTION_SET_IDENTITY =
            "com.example.disaster_mesh.SET_IDENTITY"
        const val ACTION_SET_ACTIVE_CHAT =
            "com.example.disaster_mesh.SET_ACTIVE_CHAT"
        const val ACTION_CLEAR_ACTIVE_CHAT =
            "com.example.disaster_mesh.CLEAR_ACTIVE_CHAT"

        const val EXTRA_CONVERSATION_ID = "conversation_id"
        const val EXTRA_DISPLAY_NAME = "display_name"
        const val EXTRA_DEVICE_ID = "device_id"

        private val SERVICE_UUID: UUID =
            UUID.fromString("6e4d5a10-8b3f-4c1e-9a52-3d7f0c2b1a01")

        private val MESSAGE_UUID: UUID =
            UUID.fromString("6e4d5a10-8b3f-4c1e-9a52-3d7f0c2b1a02")

        private val IDENTITY_READ_UUID: UUID =
            UUID.fromString("6e4d5a10-8b3f-4c1e-9a52-3d7f0c2b1a03")

        private val IDENTITY_WRITE_UUID: UUID =
            UUID.fromString("6e4d5a10-8b3f-4c1e-9a52-3d7f0c2b1a04")
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private var bluetoothGattServer: BluetoothGattServer? = null
    private var advertiserCallback: AdvertiseCallback? = null

    private var localDisplayName = "DisasterMesh User"
    private var localDeviceId = ""

    private val peerNames = mutableMapOf<String, String>()
    private val peerDeviceIds = mutableMapOf<String, String>()

    private var activeConversationId: String? = null

    private val messageCharacteristic =
        BluetoothGattCharacteristic(
            MESSAGE_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )

    private val identityReadCharacteristic =
        BluetoothGattCharacteristic(
            IDENTITY_READ_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )

    private val identityWriteCharacteristic =
        BluetoothGattCharacteristic(
            IDENTITY_WRITE_UUID,
            BluetoothGattCharacteristic.PROPERTY_WRITE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )

    override fun onCreate() {
        super.onCreate()

        loadSavedIdentity()
        createNotificationChannels()

        Log.d(TAG, "DisasterMesh foreground service created")
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {

        val action = intent?.action

        if (action == ACTION_STOP) {
            stopBleAdvertising()
            stopGattServer()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val requestedName =
            intent?.getStringExtra(EXTRA_DISPLAY_NAME)

        val requestedDeviceId =
            intent?.getStringExtra(EXTRA_DEVICE_ID)

        if (!requestedName.isNullOrBlank()) {
            localDisplayName = requestedName.trim()
        }

        if (!requestedDeviceId.isNullOrBlank()) {
            localDeviceId = requestedDeviceId.trim()
        }

        updateLocalIdentityCharacteristic()

        startServiceForeground()

        when (action) {

            ACTION_SET_IDENTITY -> {
                Log.d(
                    TAG,
                    "Local identity updated: $localDisplayName"
                )
            }

            ACTION_SET_ACTIVE_CHAT -> {
                activeConversationId = intent
                    ?.getStringExtra(EXTRA_CONVERSATION_ID)
                    ?.trim()
                    ?.lowercase()
                    ?.takeIf { it.isNotEmpty() }

                Log.d(
                    TAG,
                    "Active chat set: $activeConversationId"
                )
            }

            ACTION_CLEAR_ACTIVE_CHAT -> {
                activeConversationId = null
                Log.d(TAG, "Active chat cleared")
            }

            ACTION_START -> {
                startGattServer()
                startBleAdvertising()
            }

            else -> {
                Log.d(
                    TAG,
                    "Service started without a specific action"
                )
            }
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // -------------------------------------------------------------------------
    // Local identity
    // -------------------------------------------------------------------------

    private fun updateLocalIdentityCharacteristic() {
        val identityJson = JSONObject().apply {
            put("name", localDisplayName)
            put("deviceId", localDeviceId)
        }

        identityReadCharacteristic.value =
            identityJson.toString().toByteArray(Charsets.UTF_8)
    }

    // -------------------------------------------------------------------------
    // Notification channels
    // -------------------------------------------------------------------------

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)

        val serviceChannel = NotificationChannel(
            SERVICE_NOTIFICATION_CHANNEL,
            "DisasterMesh Background Service",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description =
                "Keeps DisasterMesh available for nearby connections"
        }

        val messageChannel = NotificationChannel(
            MESSAGE_NOTIFICATION_CHANNEL,
            "Chat Messages",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description =
                "Notifications for incoming DisasterMesh messages"
        }

        val connectionChannel = NotificationChannel(
            CONNECTION_NOTIFICATION_CHANNEL,
            "Nearby Connections",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description =
                "Notifications when another DisasterMesh user connects"
        }

        manager.createNotificationChannel(serviceChannel)
        manager.createNotificationChannel(messageChannel)
        manager.createNotificationChannel(connectionChannel)
    }

    // -------------------------------------------------------------------------
    // Foreground notification
    // -------------------------------------------------------------------------

    private fun startServiceForeground() {
        val notification = Notification.Builder(
            this,
            SERVICE_NOTIFICATION_CHANNEL
        )
            .setContentTitle("DisasterMesh is active")
            .setContentText(
                "Listening for nearby DisasterMesh devices"
            )
            .setSmallIcon(
                android.R.drawable.stat_sys_data_bluetooth
            )
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                SERVICE_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(
                SERVICE_NOTIFICATION_ID,
                notification
            )
        }
    }

    // -------------------------------------------------------------------------
    // Bluetooth permission checks
    // -------------------------------------------------------------------------

    private fun hasBluetoothConnectPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasBluetoothAdvertisePermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(
                Manifest.permission.BLUETOOTH_ADVERTISE
            ) == PackageManager.PERMISSION_GRANTED
    }

    // -------------------------------------------------------------------------
    // GATT server
    // -------------------------------------------------------------------------

    private fun startGattServer() {
        if (bluetoothGattServer != null) {
            Log.d(TAG, "GATT server is already running")
            return
        }

        if (!hasBluetoothConnectPermission()) {
            Log.e(TAG, "BLUETOOTH_CONNECT permission is missing")
            return
        }

        try {
            val bluetoothManager =
                getSystemService(BLUETOOTH_SERVICE) as BluetoothManager

            val adapter = bluetoothManager.adapter

            if (adapter == null || !adapter.isEnabled) {
                Log.e(TAG, "Bluetooth is unavailable or disabled")
                return
            }

            bluetoothGattServer = bluetoothManager.openGattServer(
                this,
                gattServerCallback
            )

            val service = BluetoothGattService(
                SERVICE_UUID,
                BluetoothGattService.SERVICE_TYPE_PRIMARY
            )

            service.addCharacteristic(messageCharacteristic)
            service.addCharacteristic(identityReadCharacteristic)
            service.addCharacteristic(identityWriteCharacteristic)

            updateLocalIdentityCharacteristic()

            val added =
                bluetoothGattServer?.addService(service) ?: false

            if (added) {
                Log.d(TAG, "GATT service added successfully")
            } else {
                Log.e(TAG, "Could not add GATT service")
            }

        } catch (e: SecurityException) {
            Log.e(TAG, "GATT permission error: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "GATT server error: ${e.message}", e)
        }
    }

    private val gattServerCallback =
        object : BluetoothGattServerCallback() {

            override fun onConnectionStateChange(
                device: BluetoothDevice,
                status: Int,
                newState: Int
            ) {
                super.onConnectionStateChange(
                    device,
                    status,
                    newState
                )

                Log.d(
                    TAG,
                    "Connection state: $newState, status: $status"
                )

                if (newState == BluetoothGatt.STATE_CONNECTED) {

                    val deviceName = try {
                        if (hasBluetoothConnectPermission()) {
                            device.name ?: "Nearby device"
                        } else {
                            "Nearby device"
                        }
                    } catch (_: SecurityException) {
                        "Nearby device"
                    }

                    showConnectionNotification(
                        device.address,
                        deviceName
                    )

                } else if (
                    newState == BluetoothGatt.STATE_DISCONNECTED
                ) {
                    Log.d(
                        TAG,
                        "A device disconnected: ${device.address}"
                    )
                }
            }

            override fun onCharacteristicWriteRequest(
                device: BluetoothDevice,
                requestId: Int,
                characteristic: BluetoothGattCharacteristic,
                preparedWrite: Boolean,
                responseNeeded: Boolean,
                offset: Int,
                value: ByteArray
            ) {
                super.onCharacteristicWriteRequest(
                    device,
                    requestId,
                    characteristic,
                    preparedWrite,
                    responseNeeded,
                    offset,
                    value
                )

                try {
                    val receivedText =
                        String(value, Charsets.UTF_8)

                    if (characteristic.uuid == MESSAGE_UUID) {

                        Log.d(TAG, "Incoming message received")

                        sendEventToFlutter(
                            mapOf(
                                "senderAddress" to device.address,
                                "message" to receivedText
                            )
                        )

                        val senderName =
                            peerNames[device.address]
                                ?: "Nearby device"

                        val senderDeviceId =
                            peerDeviceIds[device.address]
                                ?.lowercase()

                        val activeId =
                            activeConversationId?.lowercase()

                        val isActiveConversation =
                            activeId != null &&
                                (
                                    activeId == senderDeviceId ||
                                    activeId ==
                                        device.address.lowercase()
                                )

                        if (!isActiveConversation) {
                            showMessageNotification(
                                senderAddress = device.address,
                                senderName = senderName,
                                message = receivedText,
                                conversationId = senderDeviceId
                                    ?: device.address.lowercase()
                            )

                            Log.d(
                                TAG,
                                "Message notification displayed"
                            )
                        } else {
                            Log.d(
                                TAG,
                                "Notification suppressed: chat is already open"
                            )
                        }

                    } else if (
                        characteristic.uuid == IDENTITY_WRITE_UUID
                    ) {

                        val identity = JSONObject(receivedText)

                        val name = identity.optString(
                            "name",
                            "Nearby device"
                        )

                        val deviceId = identity.optString(
                            "deviceId",
                            ""
                        )

                        peerNames[device.address] = name

                        if (deviceId.isNotBlank()) {
                            peerDeviceIds[device.address] =
                                deviceId.lowercase()
                        }

                        Log.d(
                            TAG,
                            "Peer identity received: $name ($deviceId)"
                        )

                        sendEventToFlutter(
                            mapOf(
                                "eventType" to "peer_identity",
                                "senderAddress" to device.address,
                                "name" to name,
                                "deviceId" to deviceId
                            )
                        )

                        showConnectionNotification(
                            device.address,
                            name
                        )
                    }

                } catch (e: Exception) {
                    Log.e(
                        TAG,
                        "Error processing GATT write: ${e.message}",
                        e
                    )
                }

                if (responseNeeded) {
                    try {
                        bluetoothGattServer?.sendResponse(
                            device,
                            requestId,
                            BluetoothGatt.GATT_SUCCESS,
                            offset,
                            null
                        )
                    } catch (e: SecurityException) {
                        Log.e(
                            TAG,
                            "Could not send GATT response: ${e.message}"
                        )
                    }
                }
            }

            override fun onCharacteristicReadRequest(
                device: BluetoothDevice,
                requestId: Int,
                offset: Int,
                characteristic: BluetoothGattCharacteristic
            ) {
                super.onCharacteristicReadRequest(
                    device,
                    requestId,
                    offset,
                    characteristic
                )

                if (characteristic.uuid == IDENTITY_READ_UUID) {
                    try {
                        val identityJson = JSONObject().apply {
                            put("name", localDisplayName)
                            put("deviceId", localDeviceId)
                        }

                        val identityBytes =
                            identityJson.toString()
                                .toByteArray(Charsets.UTF_8)

                        bluetoothGattServer?.sendResponse(
                            device,
                            requestId,
                            BluetoothGatt.GATT_SUCCESS,
                            offset,
                            identityBytes
                        )

                    } catch (e: Exception) {
                        Log.e(
                            TAG,
                            "Identity read error: ${e.message}",
                            e
                        )
                    }
                }
            }
        }

    private fun stopGattServer() {
        try {
            bluetoothGattServer?.close()
        } catch (e: SecurityException) {
            Log.e(
                TAG,
                "Could not close GATT server: ${e.message}"
            )
        }

        bluetoothGattServer = null
        Log.d(TAG, "GATT server stopped")
    }

    // -------------------------------------------------------------------------
    // BLE advertising
    // -------------------------------------------------------------------------

    private fun startBleAdvertising() {
        if (advertiserCallback != null) {
            Log.d(TAG, "BLE advertising is already running")
            return
        }

        if (!hasBluetoothAdvertisePermission()) {
            Log.e(TAG, "BLUETOOTH_ADVERTISE permission is missing")
            return
        }

        try {
            val bluetoothManager =
                getSystemService(BLUETOOTH_SERVICE) as BluetoothManager

            val advertiser =
                bluetoothManager.adapter?.bluetoothLeAdvertiser

            if (advertiser == null) {
                Log.e(TAG, "BLE advertiser is unavailable")
                return
            }

            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(
                    AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY
                )
                .setConnectable(true)
                .setTxPowerLevel(
                    AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM
                )
                .build()

            val advertiseData = AdvertiseData.Builder()
                .addServiceUuid(ParcelUuid(SERVICE_UUID))
                .setIncludeDeviceName(false)
                .build()

            val nameBytes = localDisplayName
                .toByteArray(Charsets.UTF_8)
                .take(25)
                .toByteArray()

            val scanResponse = AdvertiseData.Builder()
                .addManufacturerData(0xFFFF, nameBytes)
                .build()

            advertiserCallback = object : AdvertiseCallback() {

                override fun onStartSuccess(
                    settingsInEffect: AdvertiseSettings
                ) {
                    super.onStartSuccess(settingsInEffect)
                    Log.d(
                        TAG,
                        "BLE advertising started successfully"
                    )
                }

                override fun onStartFailure(errorCode: Int) {
                    super.onStartFailure(errorCode)
                    Log.e(
                        TAG,
                        "BLE advertising failed: $errorCode"
                    )
                    advertiserCallback = null
                }
            }

            advertiser.startAdvertising(
                settings,
                advertiseData,
                scanResponse,
                advertiserCallback
            )

        } catch (e: SecurityException) {
            Log.e(
                TAG,
                "Advertising permission error: ${e.message}"
            )
            advertiserCallback = null
        } catch (e: Exception) {
            Log.e(TAG, "Advertising error: ${e.message}", e)
            advertiserCallback = null
        }
    }

    private fun stopBleAdvertising() {
        if (!hasBluetoothAdvertisePermission()) {
            advertiserCallback = null
            return
        }

        try {
            val bluetoothManager =
                getSystemService(BLUETOOTH_SERVICE) as BluetoothManager

            val advertiser =
                bluetoothManager.adapter?.bluetoothLeAdvertiser

            advertiser?.stopAdvertising(advertiserCallback)

        } catch (e: SecurityException) {
            Log.e(
                TAG,
                "Could not stop advertising: ${e.message}"
            )
        }

        advertiserCallback = null
        Log.d(TAG, "BLE advertising stopped")
    }

    // -------------------------------------------------------------------------
    // Flutter event forwarding
    // -------------------------------------------------------------------------

    private fun sendEventToFlutter(event: Map<String, Any>) {
        mainHandler.post {
            DisasterMeshEventBus.send(event)
        }
    }

    // -------------------------------------------------------------------------
    // Native Android notifications
    // -------------------------------------------------------------------------

    private fun areNotificationsEnabled(): Boolean {
        val preferences = getSharedPreferences(
            "FlutterSharedPreferences",
            MODE_PRIVATE
        )

        return preferences.getBoolean(
            "flutter.notifications_enabled",
            true
        )
    }

    private fun showMessageNotification(
        senderAddress: String,
        senderName: String,
        message: String,
        conversationId: String
    ) {
        if (!areNotificationsEnabled()) return

        val notificationId = senderAddress.hashCode()

        val launchIntent = Intent(
            this,
            MainActivity::class.java
        ).apply {
            putExtra(EXTRA_CONVERSATION_ID, conversationId)
            putExtra(EXTRA_DISPLAY_NAME, senderName)

            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_IMMUTABLE
        )

        val notification = Notification.Builder(
            this,
            MESSAGE_NOTIFICATION_CHANNEL
        )
            .setContentTitle(senderName)
            .setContentText(message)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setContentIntent(pendingIntent)
            .build()

        getSystemService(NotificationManager::class.java)
            .notify(notificationId, notification)
    }

    private fun showConnectionNotification(
        deviceAddress: String,
        deviceName: String
    ) {
        if (!areNotificationsEnabled()) return

        val notification = Notification.Builder(
            this,
            CONNECTION_NOTIFICATION_CHANNEL
        )
            .setContentTitle("New DisasterMesh Connection")
            .setContentText(
                "$deviceName connected to your device."
            )
            .setSmallIcon(
                android.R.drawable.stat_sys_data_bluetooth
            )
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_EVENT)
            .build()

        val notificationId = deviceAddress.hashCode() + 1

        getSystemService(NotificationManager::class.java)
            .notify(notificationId, notification)
    }

    // -------------------------------------------------------------------------
    // Saved identity
    // -------------------------------------------------------------------------

    private fun loadSavedIdentity() {
        val preferences = getSharedPreferences(
            "FlutterSharedPreferences",
            MODE_PRIVATE
        )

        localDisplayName = preferences.getString(
            "flutter.display_name",
            "DisasterMesh User"
        ) ?: "DisasterMesh User"

        localDeviceId = preferences.getString(
            "flutter.disaster_mesh_device_id",
            ""
        ) ?: ""

        Log.d(TAG, "Saved local identity loaded")
    }

    override fun onDestroy() {
        stopBleAdvertising()
        stopGattServer()

        Log.d(
            TAG,
            "DisasterMesh foreground service destroyed"
        )

        super.onDestroy()
    }
}

/**
 * Passes native BLE events to Flutter while the Flutter engine is active.
 */
object DisasterMeshEventBus {

    var eventSink:
        io.flutter.plugin.common.EventChannel.EventSink? = null

    fun send(event: Map<String, Any>) {
        eventSink?.success(event)
    }
}
