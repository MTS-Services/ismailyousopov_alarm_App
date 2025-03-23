package com.example.alarm

import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.app.Notification
import android.media.AudioFocusRequest
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import androidx.core.app.NotificationCompat
import android.os.Handler
import android.os.Looper
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.SystemClock
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicBoolean

class AlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "AlarmReceiver"
        private const val CHANNEL_ID = "alarm_channel"
        private var mediaPlayer: MediaPlayer? = null
        private var wakeLock: PowerManager.WakeLock? = null
        private var vibrator: Vibrator? = null
        private var isCurrentlyActive = AtomicBoolean(false)
        private var audioFocusRequest: AudioFocusRequest? = null
        private var activeAlarmId: Int = -1
        private var activeSoundId: Int = 1
        private var safetyTimeoutHandler: Handler? = null
        private var vibrationHandler: Handler? = null
        private var vibrationRunnable: Runnable? = null

        // Track last alarm time to prevent duplicate triggers
        private var lastAlarmTriggerTime: Long = 0
        private const val DUPLICATE_THRESHOLD_MS = 3000 // 3 seconds

        fun stopAlarm() {
            if (!isCurrentlyActive.getAndSet(false)) {
                Log.d(TAG, "Alarm already stopped, ignoring duplicate stop request")
                return
            }

            Log.d(TAG, "Stopping alarm ID: $activeAlarmId")

            // Cancel safety timeout
            safetyTimeoutHandler?.removeCallbacksAndMessages(null)

            // Stop vibration refresh
            vibrationHandler?.removeCallbacksAndMessages(null)
            vibrationRunnable = null

            // Release media player
            try {
                mediaPlayer?.apply {
                    if (isPlaying) {
                        stop()
                    }
                    release()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping media player", e)
            } finally {
                mediaPlayer = null
            }

            // Release audio focus
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
                try {
                    val audioManager = AlarmSoundService.appContext?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                    audioManager?.abandonAudioFocusRequest(audioFocusRequest!!)
                } catch (e: Exception) {
                    Log.e(TAG, "Error releasing audio focus", e)
                }
                audioFocusRequest = null
            }

            // Stop vibration
            try {
                vibrator?.cancel()
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping vibration", e)
            } finally {
                vibrator = null
            }

            // Release wake lock
            try {
                wakeLock?.apply {
                    if (isHeld) {
                        release()
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing wake lock", e)
            } finally {
                wakeLock = null
            }

            // Reset active alarm IDs
            activeAlarmId = -1
            activeSoundId = 1

            Log.d(TAG, "Alarm stopped successfully")
        }

        // Add method to check if alarm is currently active
        fun isCurrentlyActive(): Boolean {
            return isCurrentlyActive.get()
        }

        // Get active alarm ID
        fun getActiveAlarmId(): Int {
            return if (isCurrentlyActive.get()) activeAlarmId else -1
        }

        // Get active sound ID
        fun getActiveSoundId(): Int {
            return if (isCurrentlyActive.get()) activeSoundId else 1
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "Alarm received! Action: ${intent.action}")

        // Store application context for service use
        if (AlarmSoundService.appContext == null) {
            AlarmSoundService.appContext = context.applicationContext
        }

        val alarmId = intent.getIntExtra("alarmId", 0)
        val soundId = intent.getIntExtra("soundId", 1)
        val nfcRequired = intent.getBooleanExtra("nfcRequired", false)

        // Check for duplicate alarm triggers (within 3 seconds)
        val now = SystemClock.elapsedRealtime()
        if (now - lastAlarmTriggerTime < DUPLICATE_THRESHOLD_MS && alarmId == activeAlarmId) {
            Log.d(TAG, "Ignoring duplicate alarm trigger for ID: $alarmId")
            return
        }
        lastAlarmTriggerTime = now

        // Store last activation time in SharedPreferences for Flutter code to check
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit()
            .putLong("flutter.alarm_last_activated_$alarmId", System.currentTimeMillis())
            .apply()

        // If another alarm is active, stop it first
        if (isCurrentlyActive.get() && activeAlarmId != alarmId) {
            Log.d(TAG, "Stopping previous alarm before starting new one")
            stopAlarm()
        }

        // Set active state
        if (!isCurrentlyActive.getAndSet(true)) {
            // Store active alarm details
            activeAlarmId = alarmId
            activeSoundId = soundId

            // Set up safety timeout (15 minutes instead of 30)
            safetyTimeoutHandler = Handler(Looper.getMainLooper())
            safetyTimeoutHandler?.postDelayed({
                if (isCurrentlyActive.get()) {
                    Log.d(TAG, "Safety timeout reached, stopping alarm")
                    stopAlarm()

                    // Show notification that alarm was auto-stopped
                    showTimeoutNotification(context, alarmId)
                }
            }, 15 * 60 * 1000L)

            // Acquire wake lock
            acquireWakeLock(context)

            // Create notification channel for Android O and above
            createNotificationChannel(context)

            // Show notification
            showAlarmNotification(context, alarmId, soundId, nfcRequired)

            // Start the sound service
            startAlarmSoundService(context, alarmId, soundId)

            // Vibrate device
            vibrate(context, alarmId, soundId)

            // Wake up screen and dismiss keyguard
            wakeUpDevice(context)

            // Start the main activity
            launchMainActivity(context, alarmId, soundId, nfcRequired)

            // Store alarm state in SharedPreferences
            storeAlarmState(context, alarmId, soundId)
        } else {
            Log.d(TAG, "Alarm already active, refreshing notification")
            // Just refresh the notification
            showAlarmNotification(context, alarmId, soundId, nfcRequired)
        }
    }


    private fun acquireWakeLock(context: Context) {
        try {
            // Release any existing wake lock first
            wakeLock?.let {
                if (it.isHeld) {
                    try {
                        it.release()
                    } catch (e: Exception) {
                        Log.e(TAG, "Error releasing existing wake lock", e)
                    }
                }
            }

            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "alarm:AlarmWakeLock")

            // Acquire with timeout to prevent battery drain (10 minutes)
            wakeLock?.acquire(10 * 60 * 1000L)
            Log.d(TAG, "Wake lock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Error acquiring wake lock", e)
        }
    }

    private fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Alarm Channel",
                    NotificationManager.IMPORTANCE_HIGH)
                channel.description = "Channel for alarm notifications"
                channel.enableVibration(true)
                channel.enableLights(true)
                channel.lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
                channel.setBypassDnd(true)
                channel.setSound(null, null) // No sound from notification itself

                val notificationManager = context.getSystemService(NotificationManager::class.java)
                notificationManager.createNotificationChannel(channel)
                Log.d(TAG, "Notification channel created")
            } catch (e: Exception) {
                Log.e(TAG, "Error creating notification channel", e)
            }
        }
    }

    private fun showAlarmNotification(context: Context, alarmId: Int, soundId: Int, nfcRequired: Boolean) {
        try {
            // First, cancel any existing Flutter notifications
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // Cancel Flutter notification IDs (30000 range and 888)
            notificationManager.cancel(30000 + alarmId)
            notificationManager.cancel(888)
            // Also cancel any existing notification with our ID to avoid duplicates
            notificationManager.cancel(20000 + alarmId)
            notificationManager.cancel(10000) // Cancel the AlarmSoundService notification ID

            // Store that we're using native notification
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit()
                .putBoolean("flutter.using_native_notification", true)
                .putString("flutter.notification_handler", "native")
                .apply()

            // Create an intent that will directly open the stop alarm screen
            val stopIntent = Intent(context, MainActivity::class.java).apply {
                action = "com.example.alarm.STOP_ALARM"
                putExtra("alarmId", alarmId)
                putExtra("soundId", soundId)
                putExtra("fromAlarm", true)
                putExtra("directToStop", true)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            val stopPendingIntent = PendingIntent.getActivity(
                context,
                alarmId + 1000, // Use a different request code to avoid conflicts
                stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

            // Create the full screen intent
            val fullScreenIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("alarmId", alarmId)
                putExtra("soundId", soundId)
                putExtra("fromAlarm", true)
                putExtra("nfcRequired", nfcRequired)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            val fullScreenPendingIntent = PendingIntent.getActivity(
                context,
                alarmId,
                fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

            // Create snooze intent
            val snoozeIntent = Intent(context, MainActivity::class.java).apply {
                action = "com.example.alarm.SNOOZE_ALARM"
                putExtra("alarmId", alarmId)
                putExtra("soundId", soundId)
                putExtra("fromAlarm", true)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }

            val snoozePendingIntent = PendingIntent.getActivity(
                context,
                alarmId + 2000,
                snoozeIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

            val title = "Alarm"
            val contentText = if (nfcRequired) "Scan NFC tag to stop alarm" else "Time to wake up!"

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(contentText)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setFullScreenIntent(fullScreenPendingIntent, true)
                .setAutoCancel(false)
                .setOngoing(true)
                .setSound(null) // No sound from notification itself
                .addAction(R.mipmap.ic_launcher, "Stop", stopPendingIntent)
                .addAction(R.mipmap.ic_launcher, "Snooze", snoozePendingIntent)

            // Make the notification sticky
            val notification = builder.build()
            notification.flags = notification.flags or Notification.FLAG_INSISTENT or Notification.FLAG_NO_CLEAR

            // Use a consistent notification ID that will be used by both AlarmReceiver and AlarmSoundService
            val notificationId = 20000 + alarmId
            notificationManager.notify(notificationId, notification)
            Log.d(TAG, "Alarm notification shown for alarm ID: $alarmId with notification ID: $notificationId")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing alarm notification", e)
        }
    }






    private fun showTimeoutNotification(context: Context, alarmId: Int) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }

            val pendingIntent = PendingIntent.getActivity(
                context,
                alarmId + 3000,
                openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Alarm Auto-Stopped")
                .setContentText("Your alarm was automatically stopped after 15 minutes")
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)

            notificationManager.notify(40000 + alarmId, builder.build()) // Use 40000 range for timeout notifications
        } catch (e: Exception) {
            Log.e(TAG, "Error showing timeout notification", e)
        }
    }


    private fun startAlarmSoundService(context: Context, alarmId: Int, soundId: Int) {
        try {
            // Start the foreground service to play sound
            val serviceIntent = Intent(context, AlarmSoundService::class.java).apply {
                putExtra("soundId", soundId)
                putExtra("alarmId", alarmId)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }

            Log.d(TAG, "Started alarm sound service for alarm ID: $alarmId, sound ID: $soundId")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting alarm sound service", e)

            // Fallback: play sound directly if service fails
            playAlarmSoundFallback(context, soundId)
        }
    }

    private fun playAlarmSoundFallback(context: Context, soundId: Int) {
        try {
            Log.d(TAG, "Using fallback sound playback for sound ID: $soundId")

            // Clean up any existing media player
            mediaPlayer?.apply {
                if (isPlaying) {
                    stop()
                }
                release()
            }

            mediaPlayer = MediaPlayer()

            // Set up audio attributes for alarm
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                mediaPlayer?.setAudioAttributes(audioAttributes)
            } else {
                @Suppress("DEPRECATION")
                mediaPlayer?.setAudioStreamType(AudioManager.STREAM_ALARM)
            }

            // Request audio focus
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()

                audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(audioAttributes)
                    .setAcceptsDelayedFocusGain(true)
                    .setOnAudioFocusChangeListener { }
                    .build()

                val result = audioManager.requestAudioFocus(audioFocusRequest!!)
                if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                    Log.w(TAG, "Audio focus not granted")
                }
            }

            // Determine which sound to play
            val soundResId = when (soundId) {
                1 -> R.raw.sound_1
                2 -> R.raw.sound_2
                3 -> R.raw.sound_3
                4 -> R.raw.sound_4
                5 -> R.raw.sound_5
                6 -> R.raw.sound_6
                7 -> R.raw.sound_7
                8 -> R.raw.sound_8
                else -> R.raw.sound_1
            }

            // Prepare and play the sound
            val assetFileDescriptor = context.resources.openRawResourceFd(soundResId)
            mediaPlayer?.apply {
                setDataSource(assetFileDescriptor.fileDescriptor, assetFileDescriptor.startOffset, assetFileDescriptor.length)
                isLooping = true
                setVolume(1.0f, 1.0f)
                prepare()
                start()
            }
            assetFileDescriptor.close()

            Log.d(TAG, "Fallback sound playback started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error in fallback sound playback", e)
        }
    }

    private fun vibrate(context: Context, alarmId: Int, soundId: Int) {
        try {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (vibrator == null || !vibrator.hasVibrator()) {
                Log.d(TAG, "Device does not support vibration")
                return
            }

            // Store reference in companion object
            Companion.vibrator = vibrator

            // Create a pattern with increasing intensity
            val pattern = longArrayOf(0, 500, 500, 600, 600, 700, 700, 800, 800)

            // Start vibration
            startVibrationPattern(vibrator, pattern)

            // Set up a periodic refresh to ensure vibration continues
            vibrationHandler = Handler(Looper.getMainLooper())
            vibrationRunnable = object : Runnable {
                override fun run() {
                    if (isCurrentlyActive.get() && vibrator != null) {
                        // Restart vibration to ensure it continues
                        startVibrationPattern(vibrator, pattern)
                        Log.d(TAG, "Refreshed vibration pattern")

                        // Check again in 5 seconds
                        vibrationHandler?.postDelayed(this, 5000)
                    }
                }
            }

            // Start the periodic check
            vibrationHandler?.postDelayed(vibrationRunnable!!, 5000)

            // Save active alarm state
            storeAlarmState(context, alarmId, soundId)

            Log.d(TAG, "Started vibration with periodic refresh")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting vibration", e)
        }
    }

    private fun startVibrationPattern(vibrator: Vibrator, pattern: LongArray) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val vibe = VibrationEffect.createWaveform(pattern, 0)
                vibrator.vibrate(vibe)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting vibration pattern", e)
        }
    }

    private fun wakeUpDevice(context: Context) {
        try {
            // Wake up screen
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val screenWakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                "alarm:ScreenWakeLock")

            // Only hold for 3 seconds - just enough to wake the screen
            screenWakeLock.acquire(3 * 1000L)

            // We'll handle keyguard dismissal in MainActivity

            Log.d(TAG, "Woke up device screen")
        } catch (e: Exception) {
            Log.e(TAG, "Error waking up device", e)
        }
    }

    private fun launchMainActivity(context: Context, alarmId: Int, soundId: Int, nfcRequired: Boolean) {
        try {
            val intent = Intent(context, MainActivity::class.java).apply {
                putExtra("alarmId", alarmId)
                putExtra("soundId", soundId)
                putExtra("fromAlarm", true)
                putExtra("nfcRequired", nfcRequired)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            context.startActivity(intent)
            Log.d(TAG, "Launched main activity with alarm data: alarmId=$alarmId, soundId=$soundId")
        } catch (e: Exception) {
            Log.e(TAG, "Error launching main activity", e)

            // If we can't launch the activity, make sure the notification is visible
            showAlarmNotification(context, alarmId, soundId, nfcRequired)
        }
    }

    private fun storeAlarmState(context: Context, alarmId: Int, soundId: Int) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.edit()
                .putInt("flutter.active_alarm_id", alarmId)
                .putInt("flutter.active_alarm_sound", soundId)
                .putLong("flutter.alarm_start_time", System.currentTimeMillis())
                .putLong("flutter.alarm_last_activated_$alarmId", System.currentTimeMillis())
                .apply()

            Log.d(TAG, "Stored alarm state in SharedPreferences: alarmId=$alarmId, soundId=$soundId")
        } catch (e: Exception) {
            Log.e(TAG, "Error storing alarm state", e)
        }
    }

}

