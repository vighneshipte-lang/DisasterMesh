
package com.example.disaster_mesh

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val methodChannelName = "disaster_mesh/ble_advertising"
    private val eventChannelName = "disaster_mesh/ble_messages"
    private val notificationChannelName =
        "disaster_mesh/notification_navigation"

    private var localDisplayName = "DisasterMesh User"
    private var localDeviceId = ""

    private var notificationEventSink: EventChannel.EventSink? = null
    private var pendingNotificationData: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "setIdentity" -> {
                    val name = call.argument<String>("name")
                    val deviceId = call.argument<String>("deviceId")

                    if (name.isNullOrBlank() || deviceId.isNullOrBlank()) {
                        result.error(
                            "INVALID_IDENTITY",
                            "Display name and device ID are required.",
                            null
                        )
                    } else {
                        localDisplayName = name.trim()
                        localDeviceId = deviceId.trim()

                        getSharedPreferences(
                            "FlutterSharedPreferences",
                            MODE_PRIVATE
                        ).edit()
                            .putString("flutter.display_name", localDisplayName)
                            .putString(
                                "flutter.disaster_mesh_device_id",
                                localDeviceId
                            )
                            .apply()

                        Log.d(
                            "DisasterMesh",
                            "Local identity saved: $localDisplayName ($localDeviceId)"
                        )

                        result.success(true)
                    }
                }

                "setActiveChat" -> {
                    val conversationId =
                        call.argument<String>("conversationId")

                    if (conversationId.isNullOrBlank()) {
                        result.error(
                            "INVALID_CONVERSATION",
                            "Conversation ID is required.",
                            null
                        )
                    } else {
                        updateActiveChat(
                            DisasterMeshBleService.ACTION_SET_ACTIVE_CHAT,
                            conversationId.trim(),
                            result
                        )
                    }
                }

                "clearActiveChat" -> {
                    updateActiveChat(
                        DisasterMeshBleService.ACTION_CLEAR_ACTIVE_CHAT,
                        null,
                        result
                    )
                }

                "startAdvertising",
                "startGattServer" -> startBleService(result)

                "stopAdvertising",
                "stopGattServer" -> stopBleService(result)

                // Flutter calls this when it starts to check whether
                // Android launched the app from a message notification.
                "getInitialNotification" -> {
                    result.success(readNotificationData(intent))
                }

                else -> result.notImplemented()
            }
        }

        // Existing BLE event channel.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventChannelName
        ).setStreamHandler(object : EventChannel.StreamHandler {

            override fun onListen(
                arguments: Any?,
                events: EventChannel.EventSink?
            ) {
                DisasterMeshEventBus.eventSink = events

                Log.d(
                    "DisasterMesh",
                    "Flutter BLE event listener attached"
                )
            }

            override fun onCancel(arguments: Any?) {
                DisasterMeshEventBus.eventSink = null

                Log.d(
                    "DisasterMesh",
                    "Flutter BLE event listener detached"
                )
            }
        })

        // Separate event channel for notification taps.
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationChannelName
        ).setStreamHandler(object : EventChannel.StreamHandler {

            override fun onListen(
                arguments: Any?,
                events: EventChannel.EventSink?
            ) {
                notificationEventSink = events

                Log.d(
                    "DisasterMesh",
                    "Notification navigation listener attached"
                )

                // Deliver a notification tap that happened before
                // Flutter attached its event listener.
                pendingNotificationData?.let { data ->
                    events?.success(data)
                    pendingNotificationData = null
                }
            }

            override fun onCancel(arguments: Any?) {
                notificationEventSink = null

                Log.d(
                    "DisasterMesh",
                    "Notification navigation listener detached"
                )
            }
        })
    }

    // -------------------------------------------------------------------------
    // Read notification data from an Android Intent
    // -------------------------------------------------------------------------

    private fun readNotificationData(
        sourceIntent: Intent?
    ): Map<String, String>? {

        if (sourceIntent == null) return null

        val conversationId = sourceIntent.getStringExtra(
            DisasterMeshBleService.EXTRA_CONVERSATION_ID
        )

        val displayName = sourceIntent.getStringExtra(
            DisasterMeshBleService.EXTRA_DISPLAY_NAME
        )

        if (conversationId.isNullOrBlank()) {
            return null
        }

        // Remove the extras so the same notification is not processed twice.
        sourceIntent.removeExtra(
            DisasterMeshBleService.EXTRA_CONVERSATION_ID
        )

        sourceIntent.removeExtra(
            DisasterMeshBleService.EXTRA_DISPLAY_NAME
        )

        Log.d(
            "DisasterMesh",
            "Notification opened for: $displayName ($conversationId)"
        )

        return mapOf(
            "conversationId" to conversationId,
            "displayName" to (displayName ?: "Nearby device")
        )
    }

    // -------------------------------------------------------------------------
    // Handle notification taps while the app is already running
    // -------------------------------------------------------------------------

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)

        setIntent(intent)

        val notificationData = readNotificationData(intent)

        if (notificationData != null) {
            if (notificationEventSink != null) {
                notificationEventSink?.success(notificationData)
            } else {
                pendingNotificationData = notificationData
            }

            Log.d(
                "DisasterMesh",
                "Notification tap forwarded to Flutter"
            )
        }
    }

    // -------------------------------------------------------------------------
    // Update active conversation in the native BLE service
    // -------------------------------------------------------------------------

    private fun updateActiveChat(
        action: String,
        conversationId: String?,
        result: MethodChannel.Result
    ) {
        try {
            val serviceIntent = Intent(
                this,
                DisasterMeshBleService::class.java
            ).apply {
                this.action = action

                if (conversationId != null) {
                    putExtra(
                        DisasterMeshBleService.EXTRA_CONVERSATION_ID,
                        conversationId
                    )
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }

            Log.d(
                "DisasterMesh",
                "Active chat updated: ${conversationId ?: "none"}"
            )

            result.success(true)

        } catch (e: Exception) {
            Log.e(
                "DisasterMesh",
                "Unable to update active chat: ${e.message}",
                e
            )

            result.error(
                "ACTIVE_CHAT_ERROR",
                e.message,
                null
            )
        }
    }

    // -------------------------------------------------------------------------
    // Start foreground BLE service
    // -------------------------------------------------------------------------

    private fun startBleService(result: MethodChannel.Result) {

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {

            if (checkSelfPermission(
                    Manifest.permission.BLUETOOTH_CONNECT
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                result.error(
                    "PERMISSION_DENIED",
                    "Bluetooth connect permission is required.",
                    null
                )
                return
            }

            if (checkSelfPermission(
                    Manifest.permission.BLUETOOTH_ADVERTISE
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                result.error(
                    "PERMISSION_DENIED",
                    "Bluetooth advertising permission is required.",
                    null
                )
                return
            }
        }

        try {
            val serviceIntent = Intent(
                this,
                DisasterMeshBleService::class.java
            ).apply {
                action = DisasterMeshBleService.ACTION_START

                putExtra(
                    DisasterMeshBleService.EXTRA_DISPLAY_NAME,
                    localDisplayName
                )

                putExtra(
                    DisasterMeshBleService.EXTRA_DEVICE_ID,
                    localDeviceId
                )
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
            } else {
                startService(serviceIntent)
            }

            Log.d(
                "DisasterMesh",
                "Foreground BLE service start requested"
            )

            result.success(true)

        } catch (e: SecurityException) {
            Log.e(
                "DisasterMesh",
                "Unable to start BLE service: ${e.message}"
            )

            result.error(
                "SERVICE_PERMISSION_ERROR",
                e.message,
                null
            )

        } catch (e: Exception) {
            Log.e(
                "DisasterMesh",
                "Unable to start BLE service: ${e.message}",
                e
            )

            result.error(
                "SERVICE_START_ERROR",
                e.message,
                null
            )
        }
    }

    // -------------------------------------------------------------------------
    // Stop foreground BLE service
    // -------------------------------------------------------------------------

    private fun stopBleService(result: MethodChannel.Result) {

        try {
            val serviceIntent = Intent(
                this,
                DisasterMeshBleService::class.java
            ).apply {
                action = DisasterMeshBleService.ACTION_STOP
            }

            startService(serviceIntent)

            Log.d(
                "DisasterMesh",
                "Foreground BLE service stop requested"
            )

            result.success(true)

        } catch (e: Exception) {
            Log.e(
                "DisasterMesh",
                "Unable to stop BLE service: ${e.message}",
                e
            )

            result.error(
                "SERVICE_STOP_ERROR",
                e.message,
                null
            )
        }
    }

    // -------------------------------------------------------------------------
    // Activity cleanup
    // -------------------------------------------------------------------------

    override fun onDestroy() {
        // Do not stop BLE here. The foreground service must remain active.
        super.onDestroy()
    }
}
