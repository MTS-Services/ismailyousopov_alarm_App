package com.example.alarm

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.app.PendingIntent
import android.app.AlarmManager
import android.view.WindowManager
import android.app.KeyguardManager
import android.content.Context
import android.os.PowerManager
import android.app.NotificationManager
import android.os.Vibrator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import android.os.Handler
import android.os.Looper
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity: FlutterActivity() {
    private val TAG = "MainActivity"
    private val CHANNEL = "com.example.alarm/background_channel"
    private val WAKE_LOCK_CHANNEL = "com.your.package/wake_lock"
    private val ALARM_MANAGER_CHANNEL = "com.your.package/alarm_manager"

    private var wakeLock: PowerManager.WakeLock? = null


    private fun isNativeNotificationActive(alarmId: Int): Boolean {
        // Check if AlarmReceiver has an active notification
        val isReceiverActive = AlarmReceiver.isCurrentlyActive() &&
                AlarmReceiver.getActiveAlarmId() == alarmId

        // Check if AlarmSoundService is running for this alarm
        val isServiceRunning = isServiceRunning(AlarmSoundService::class.java)

        return isReceiverActive || isServiceRunning
    }


    private fun cleanupDuplicateNotifications() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val activeAlarmId = prefs.getInt("flutter.active_alarm_id", -1)

            if (activeAlarmId != -1) {
                // If we have an active alarm, make sure we only have one notification
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                // Keep only the notification with ID 20000 + alarmId
                notificationManager.cancel(10000)  // Cancel AlarmSoundService default notification
                notificationManager.cancel(30000 + activeAlarmId)  // Cancel Flutter notification
                notificationManager.cancel(888)  // Cancel Flutter service notification
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error cleaning up duplicate notifications", e)
        }
    }


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Set alarm notification visibility
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }

        // Handle background service channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {

                "isNativeNotificationActive" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    result.success(isNativeNotificationActive(alarmId))
                }

                "cancelNotification" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                    // Cancel all possible notification IDs for this alarm
                    notificationManager.cancel(10000)           // Service notification
                    notificationManager.cancel(20000 + alarmId) // Main alarm notification
                    notificationManager.cancel(30000 + alarmId) // Flutter notification
                    notificationManager.cancel(40000 + alarmId) // Timeout notification
                    
                    // Also cancel all notifications to be safe
                    notificationManager.cancelAll()

                    result.success(true)
                }


                "bringToForeground" -> {
                    bringToForeground()
                    result.success(true)
                }
                
                "startForegroundService" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    val soundId = call.argument<Int>("soundId") ?: 1
                    startAlarmService(alarmId, soundId)
                    result.success(true)
                }

                "stopVibration" -> {
                    stopVibration()
                    result.success(true)
                }
                
                "stopAlarmReceiver" -> {
                    // Explicitly stop the AlarmReceiver to stop vibration and sound
                    try {
                        AlarmReceiver.stopAlarm()
                        Log.d(TAG, "AlarmReceiver stopped successfully")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error stopping AlarmReceiver", e)
                        result.success(false)
                    }
                }
                
                "stopAlarmService" -> {
                    // Stop the alarm service
                    try {
                        stopAlarmService()
                        Log.d(TAG, "Alarm service stopped successfully")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error stopping alarm service", e)
                        result.success(false)
                    }
                }
                
                "cancelAllNotifications" -> {
                    cancelAllNotifications()
                    result.success(true)
                }
                
                "forceStopService" -> {
                    stopAlarmService()
                    result.success(true)
                }

                "cancelExactAlarm" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: -1
                    if (alarmId != -1) {
                        cancelExactAlarm(alarmId)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }

                "isAlarmActive" -> {
                    // Check multiple indicators to determine if alarm is active
                    val isWakeLockHeld = wakeLock != null && wakeLock!!.isHeld
                    val isAlarmReceiverActive = AlarmReceiver.isCurrentlyActive()
                    val isVibrating = checkVibrationActive()

                    val isActive = isWakeLockHeld || isAlarmReceiverActive || isVibrating
                    Log.d(TAG, "Alarm active check: WakeLock=$isWakeLockHeld, Receiver=$isAlarmReceiverActive, Vibrating=$isVibrating")

                    result.success(isActive)
                }
                
                "getAlarmLaunchData" -> {
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val fromAction = prefs.getBoolean("flutter.from_notification_action", false)
                    val pendingAlarmId = prefs.getInt("flutter.pending_alarm_id", -1)
                    val pendingSoundId = prefs.getInt("flutter.pending_sound_id", 1)
                    val directToStop = prefs.getBoolean("flutter.direct_to_stop", false)

                    val data = if (fromAction && pendingAlarmId != -1) {
                        mapOf(
                            "alarmId" to pendingAlarmId,
                            "soundId" to pendingSoundId,
                            "fromAlarm" to true,
                            "directToStop" to directToStop
                        )
                    } else {
                        intent.extras?.let {
                            if (it.containsKey("fromAlarm")) {
                                mapOf(
                                    "alarmId" to it.getInt("alarmId", 0),
                                    "soundId" to it.getInt("soundId", 1),
                                    "fromAlarm" to it.getBoolean("fromAlarm", false),
                                    "directToStop" to it.getBoolean("directToStop", false)
                                )
                            } else null
                        }
                    }

                    // Clear the flags after reading
                    if (fromAction) {
                        prefs.edit()
                            .remove("flutter.from_notification_action")
                            .remove("flutter.pending_alarm_id")
                            .remove("flutter.pending_sound_id")
                            .remove("flutter.direct_to_stop")
                            .apply()
                    }

                    result.success(data)
                }
                
                "requestNotificationPermissions" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val permission = android.Manifest.permission.POST_NOTIFICATIONS
                        if (ContextCompat.checkSelfPermission(this, permission) != 
                                PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(permission), 100)
                        }
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // Handle wake lock channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKE_LOCK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquirePersistentWakeLock" -> {
                    acquireWakeLock()
                    result.success(true)
                }
                "releaseWakeLock" -> {
                    releaseWakeLock()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Handle alarm manager channel - RE-ENABLED as backup for when app is closed
        // Primary: Flutter Alarm package, Backup: Native scheduling
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_MANAGER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "scheduleExactAlarm") {
                val alarmId = call.argument<Int>("alarmId") ?: 0
                val triggerAtMillis = call.argument<Long>("triggerAtMillis") ?: 0L
                val soundId = call.argument<Int>("soundId") ?: 1
                val nfcRequired = call.argument<Boolean>("nfcRequired") ?: false

                scheduleExactAlarm(alarmId, triggerAtMillis, soundId, nfcRequired)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        cleanupDuplicateNotifications()

        // Handle screen wake and keyguard for alarms
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)

            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        // Check if launched from alarm or stop alarm action
        intent?.let {
            if (it.hasExtra("fromAlarm") || it.action == "com.example.alarm.STOP_ALARM") {
                val alarmId = it.getIntExtra("alarmId", 0)
                val soundId = it.getIntExtra("soundId", 1)
                val directToStop = it.getBooleanExtra("directToStop", false)

                // Store this data to be retrieved by Flutter
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                prefs.edit()
                    .putBoolean("flutter.from_notification_action", true)
                    .putInt("flutter.pending_alarm_id", alarmId)
                    .putInt("flutter.pending_sound_id", soundId)
                    .putBoolean("flutter.direct_to_stop", directToStop)
                    .apply()

                // Acquire wake lock
                acquireWakeLock()

                Log.d(TAG, "App launched from alarm: alarmId=$alarmId, soundId=$soundId, directToStop=$directToStop")
            }
        }
    }



    override fun onResume() {
        super.onResume()
        checkAndRestartAlarmSoundIfNeeded()
    }

    private fun checkAndRestartAlarmSoundIfNeeded() {
        val isAlarmReceiverActive = AlarmReceiver.isCurrentlyActive()

        if (isAlarmReceiverActive) {
            // Get active alarm details from SharedPreferences
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val activeAlarmId = prefs.getInt("flutter.active_alarm_id", -1)
            val activeSoundId = prefs.getInt("flutter.active_alarm_sound", 1)

            if (activeAlarmId != -1) {
                // Check if service is running
                val serviceRunning = isServiceRunning(AlarmSoundService::class.java)

                if (!serviceRunning) {
                    // Restart the sound service
                    val intent = Intent(this, AlarmSoundService::class.java).apply {
                        putExtra("soundId", activeSoundId)
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }

                    Log.d(TAG, "Restarted alarm sound service during app resume")
                }
            }
        }
    }

    private fun isServiceRunning(serviceClass: Class<*>): Boolean {
        val manager = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        for (service in manager.getRunningServices(Integer.MAX_VALUE)) {
            if (serviceClass.name == service.service.className) {
                return true
            }
        }
        return false
    }

    private fun bringToForeground() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        startActivity(intent)
        Log.d(TAG, "Bringing app to foreground")
    }

    // Check if vibration is active
    // Check if vibration is active
    // Check if vibration is active
    // Check if vibration is active - simplified version
    private fun checkVibrationActive(): Boolean {
        // We'll use a simpler approach that works on all Android versions
        return false  // Default to false and rely on other indicators
    }




    private fun stopVibration() {
        Log.d(TAG, "Stopping vibration - comprehensive approach")
        
        try {
            // Stop system vibrator
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            vibrator?.cancel()
            Log.d(TAG, "System vibrator cancelled")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping system vibrator", e)
        }

        try {
            // Stop the alarm receiver's vibration
            AlarmReceiver.stopAlarm()
            Log.d(TAG, "AlarmReceiver.stopAlarm() called")
        } catch (e: Exception) {
            Log.e(TAG, "Error calling AlarmReceiver.stopAlarm()", e)
        }

        try {
            // Also try to stop any vibration from AlarmSoundService
            val serviceIntent = Intent(this, AlarmSoundService::class.java)
            serviceIntent.action = "STOP_VIBRATION"
            startService(serviceIntent)
            Log.d(TAG, "Sent stop vibration command to AlarmSoundService")
        } catch (e: Exception) {
            Log.e(TAG, "Error sending stop vibration to service", e)
        }

        // Double-check by trying to cancel vibration again after a short delay
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                vibrator?.cancel()
                Log.d(TAG, "Double-checked vibration cancellation")
            } catch (e: Exception) {
                Log.e(TAG, "Error in double-check vibration cancellation", e)
            }
        }, 100)

        Log.d(TAG, "Vibration stop sequence completed")
    }

    private fun cancelAllNotifications() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancelAll()
        Log.d(TAG, "Cancelled all notifications")
    }


    private fun cancelExactAlarm(alarmId: Int) {
        try {
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                action = "com.example.alarm.ALARM_TRIGGERED"
                putExtra("alarmId", alarmId)
            }

            val pendingIntent = PendingIntent.getBroadcast(
                this,
                alarmId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(pendingIntent)

            Log.d(TAG, "Canceled exact alarm with ID: $alarmId")
        } catch (e: Exception) {
            Log.e(TAG, "Error canceling exact alarm: ${e.message}")
        }
    }


    private fun startAlarmService(alarmId: Int, soundId: Int) {
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            action = "com.example.alarm.ALARM_TRIGGERED"
            putExtra("alarmId", alarmId)
            putExtra("soundId", soundId)
        }
        sendBroadcast(intent)
        Log.d(TAG, "Started alarm service: alarmId=$alarmId, soundId=$soundId")
    }

    private fun stopAlarmService() {
        Log.d(TAG, "Starting alarm service shutdown sequence")
        
        // First, stop the AlarmSoundService explicitly
        try {
            val intent = Intent(this, AlarmSoundService::class.java)
            val stopped = stopService(intent)
            Log.d(TAG, "Stopping AlarmSoundService directly: success=$stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping AlarmSoundService", e)
        }
        
        // Stop the alarm receiver
        try {
            AlarmReceiver.stopAlarm()
            Log.d(TAG, "AlarmReceiver.stopAlarm() called successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error calling AlarmReceiver.stopAlarm()", e)
        }
        
        // Cancel any ongoing notifications
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
            Log.d(TAG, "Cancelled all notifications")
        } catch (e: Exception) {
            Log.e(TAG, "Error cancelling notifications", e)
        }
        
        // Make a second attempt to stop the service with a slight delay
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val intent = Intent(this, AlarmSoundService::class.java)
                stopService(intent)
                Log.d(TAG, "Second attempt to stop AlarmSoundService completed")
            } catch (e: Exception) {
                Log.e(TAG, "Error in second attempt to stop service", e)
            }
        }, 300)

        // Clear active alarm in preferences
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit()
                .remove("flutter.active_alarm_id")
                .remove("flutter.active_alarm_sound")
                .apply()
            Log.d(TAG, "Cleared active alarm from SharedPreferences")
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing SharedPreferences", e)
        }

        Log.d(TAG, "Alarm service shutdown sequence completed")
    }

    private fun acquireWakeLock() {
        if (wakeLock != null && wakeLock!!.isHeld) {
            return
        }

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "alarm:MainActivityWakeLock")
        wakeLock?.acquire(10*60*1000L) // 10 minutes
        Log.d(TAG, "Acquired wake lock")
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                wakeLock = null
                Log.d(TAG, "Released wake lock")
            }
        }
    }

    private fun scheduleExactAlarm(alarmId: Int, triggerAtMillis: Long, soundId: Int, nfcRequired: Boolean) {
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            action = "com.example.alarm.ALARM_TRIGGERED"
            putExtra("alarmId", alarmId)
            putExtra("soundId", soundId)
            putExtra("nfcRequired", nfcRequired)
        }

        // Use the exact trigger time without any adjustment to ensure precise timing
        val exactTriggerTime = triggerAtMillis

        val alarmManager = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
        val pendingIntent = android.app.PendingIntent.getBroadcast(
            this,
            alarmId,
            intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)

        // Store scheduled alarm info in SharedPreferences for recovery
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val scheduledAlarmsString = prefs.getString("flutter.scheduled_alarms", "") ?: ""

            // Parse existing alarms
            val alarmsList = mutableListOf<String>()
            if (scheduledAlarmsString.isNotEmpty()) {
                // Split by comma, but handle potential JSON formatting issues
                if (scheduledAlarmsString.startsWith("[") && scheduledAlarmsString.endsWith("]")) {
                    // It's a JSON array, parse it properly
                    try {
                        val jsonArray = org.json.JSONArray(scheduledAlarmsString)
                        for (i in 0 until jsonArray.length()) {
                            alarmsList.add(jsonArray.getString(i))
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error parsing JSON alarm data", e)
                        // Fallback to simple comma splitting if JSON parsing fails
                        alarmsList.addAll(scheduledAlarmsString.split(",").filter { it.isNotEmpty() })
                    }
                } else {
                    // Simple comma-separated list
                    alarmsList.addAll(scheduledAlarmsString.split(",").filter { it.isNotEmpty() })
                }
            }

            // Remove any existing entry for this alarm ID
            alarmsList.removeAll { it.startsWith("$alarmId:") }

            // Add the new alarm - use the exact trigger time
            val alarmInfo = "$alarmId:$soundId:$exactTriggerTime:$nfcRequired"
            alarmsList.add(alarmInfo)

            // Store as a simple comma-separated list
            val newAlarmsString = alarmsList.joinToString(",")
            prefs.edit().putString("flutter.scheduled_alarms", newAlarmsString).apply()

            Log.d(TAG, "Stored scheduled alarm: $alarmInfo, Full list: $newAlarmsString")
        } catch (e: Exception) {
            Log.e(TAG, "Error storing scheduled alarm", e)
        }

        // Schedule the alarm with exact time
        try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && alarmManager.canScheduleExactAlarms() -> {
                    // Use both methods for redundancy
                    alarmManager.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, exactTriggerTime, pendingIntent)
                    alarmManager.setAlarmClock(android.app.AlarmManager.AlarmClockInfo(exactTriggerTime, pendingIntent), pendingIntent)
                    Log.d(TAG, "Scheduled exact alarm with AlarmClock (Android 12+): ID=$alarmId, Time=$exactTriggerTime (original=$triggerAtMillis)")
                }
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
                    alarmManager.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, exactTriggerTime, pendingIntent)
                    Log.d(TAG, "Scheduled exact alarm with setExactAndAllowWhileIdle: ID=$alarmId, Time=$exactTriggerTime (original=$triggerAtMillis)")
                }
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT -> {
                    alarmManager.setExact(android.app.AlarmManager.RTC_WAKEUP, exactTriggerTime, pendingIntent)
                    Log.d(TAG, "Scheduled exact alarm with setExact: ID=$alarmId, Time=$exactTriggerTime (original=$triggerAtMillis)")
                }
                else -> {
                    alarmManager.set(android.app.AlarmManager.RTC_WAKEUP, exactTriggerTime, pendingIntent)
                    Log.d(TAG, "Scheduled alarm with set: ID=$alarmId, Time=$exactTriggerTime (original=$triggerAtMillis)")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error scheduling alarm", e)
        }
    }


    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
        Log.d(TAG, "MainActivity destroyed")
    }
}

