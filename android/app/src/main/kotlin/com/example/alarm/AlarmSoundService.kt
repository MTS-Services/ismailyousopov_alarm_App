package com.example.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

class AlarmSoundService : Service() {
    companion object {
        private const val TAG = "AlarmSoundService"
        private const val NOTIFICATION_ID = 10000  // Use 10000 range for service notifications
        private const val CHANNEL_ID = "alarm_sound_channel"
        private var isServiceRunning = false
        var appContext: Context? = null  // Store application context for static access
    }

    private var mediaPlayer: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var soundId: Int = 1
    private var alarmId: Int = 0
    private var audioFocusRequest: AudioFocusRequest? = null
    private var volumeIncreaseHandler: Handler? = null
    private var currentVolume: Float = 0.7f

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service created")

        // Create notification channel
        createNotificationChannel()

        // Acquire wake lock
        acquireWakeLock()

        // Initialize media player
        mediaPlayer = MediaPlayer()

        isServiceRunning = true
    }


    private fun startAlarmSound() {
        try {
            // Request audio focus first
            requestAudioFocus()

            // Load volume from shared preferences
            loadVolumeSetting()

            // Play the alarm sound
            playAlarmSound(soundId)

            // Don't set up automatic volume increase if user has set a specific volume
            // setupVolumeIncrease()

            Log.d(TAG, "Alarm sound started for sound ID: $soundId")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting alarm sound", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "Service start command received")

        // Extract parameters from intent
        soundId = intent?.getIntExtra("soundId", 1) ?: 1
        alarmId = intent?.getIntExtra("alarmId", 0) ?: 0

        // Cancel any Flutter notifications first
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(30000 + alarmId)
        notificationManager.cancel(888)

        // Store that we're using native notification
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("flutter.using_native_notification", true)
            .putString("flutter.notification_handler", "native")
            .apply()

        // IMPORTANT: Don't create our own notification, use the one from AlarmReceiver
        // Instead of creating a new notification, use the existing one from AlarmReceiver
        try {
            // Get the notification from AlarmReceiver
            val receiverNotificationId = 20000 + alarmId
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Alarm")
                .setContentText("Time to wake up!")
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .build()

            // Use the existing notification for the foreground service
            startForeground(receiverNotificationId, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Error using existing notification, creating fallback", e)
            // Only create a new notification as fallback if we couldn't use the existing one
            val fallbackNotification = createForegroundNotification()
            startForeground(NOTIFICATION_ID, fallbackNotification)
        }

        // Start playing sound
        startAlarmSound()

        // Return sticky so service restarts if killed
        return START_STICKY
    }




    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Alarm Sound Channel",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Channel for alarm sound playback"
                enableLights(true)
                lightColor = android.graphics.Color.RED
                importance = NotificationManager.IMPORTANCE_HIGH
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }

    private fun createForegroundNotification(): Notification {
        // Create intent to open main activity
        val intent = Intent(this, MainActivity::class.java).apply {
            action = "com.example.alarm.STOP_ALARM"
            putExtra("alarmId", alarmId)
            putExtra("soundId", soundId)
            putExtra("fromAlarm", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Create stop action
        val stopIntent = Intent(this, MainActivity::class.java).apply {
            action = "com.example.alarm.STOP_ALARM"
            putExtra("alarmId", alarmId)
            putExtra("soundId", soundId)
            putExtra("fromAlarm", true)
            putExtra("directToStop", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val stopPendingIntent = PendingIntent.getActivity(
            this,
            alarmId + 1000,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Build notification
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Alarm")
            .setContentText("Tap to stop the alarm")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pendingIntent, true)
            .setOngoing(true)
            .setAutoCancel(false)
            .addAction(R.mipmap.ic_launcher, "Stop Alarm", stopPendingIntent)
            .setContentIntent(pendingIntent)
            // Add these for better visibility
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setColorized(true)
            .setColor(0xFFFF0000.toInt())
            .setUsesChronometer(true)
            .setOnlyAlertOnce(false)

        return builder.build().apply {
            flags = flags or Notification.FLAG_INSISTENT or Notification.FLAG_NO_CLEAR
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock != null && wakeLock!!.isHeld) {
            return
        }

        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
            "alarm:SoundServiceWakeLock"
        )
        wakeLock?.acquire(30 * 60 * 1000L) // 30 minutes
        Log.d(TAG, "Wake lock acquired")
    }

    private fun playAlarmSound(soundId: Int) {
        try {
            // Release any existing media player
            mediaPlayer?.release()
            mediaPlayer = MediaPlayer()

            // Set up media player
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
            val assetFileDescriptor = resources.openRawResourceFd(soundResId)
            mediaPlayer?.apply {
                setDataSource(assetFileDescriptor.fileDescriptor, assetFileDescriptor.startOffset, assetFileDescriptor.length)
                isLooping = true
                setVolume(currentVolume, currentVolume)
                setOnPreparedListener {
                    it.start()
                    Log.d(TAG, "Media player started with volume: $currentVolume")
                }
                setOnErrorListener { _, what, extra ->
                    Log.e(TAG, "Media player error: what=$what, extra=$extra")
                    // Try to restart on error
                    Handler(Looper.getMainLooper()).postDelayed({
                        playAlarmSound(soundId)
                    }, 1000)
                    true
                }
                prepareAsync()
            }
            assetFileDescriptor.close()

            // Set up a health check to ensure sound keeps playing
            setupHealthCheck()

            Log.d(TAG, "Prepared alarm sound: $soundId")
        } catch (e: Exception) {
            Log.e(TAG, "Error playing alarm sound", e)
            // Try again after a delay
            Handler(Looper.getMainLooper()).postDelayed({
                playAlarmSound(soundId)
            }, 1000)
        }
    }

    private fun requestAudioFocus() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

            // For Android O and above, use AudioFocusRequest
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()

                audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(audioAttributes)
                    .setAcceptsDelayedFocusGain(true)
                    .setOnAudioFocusChangeListener { focusChange ->
                        when (focusChange) {
                            AudioManager.AUDIOFOCUS_LOSS -> {
                                // We don't give up audio focus for alarms
                                requestAudioFocus()
                            }
                            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                                // Temporary loss - we'll request again
                                Handler(Looper.getMainLooper()).postDelayed({
                                    requestAudioFocus()
                                }, 1000)
                            }
                        }
                    }
                    .build()

                val result = audioManager.requestAudioFocus(audioFocusRequest!!)
                if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                    Log.w(TAG, "Audio focus not granted: $result")
                }
            } else {
                // For older Android versions
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    { focusChange ->
                        // Do nothing, we want to keep playing
                    },
                    AudioManager.STREAM_ALARM,
                    AudioManager.AUDIOFOCUS_GAIN
                )
            }

            // Set stream type for older Android versions
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                @Suppress("DEPRECATION")
                mediaPlayer?.setAudioStreamType(AudioManager.STREAM_ALARM)
            } else {
                // For newer Android versions, set audio attributes
                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                mediaPlayer?.setAudioAttributes(audioAttributes)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting audio focus", e)
        }
    }

    private fun setupHealthCheck() {
        // Create a handler to periodically check if sound is still playing
        val handler = Handler(Looper.getMainLooper())
        handler.postDelayed(object : Runnable {
            override fun run() {
                if (mediaPlayer != null) {
                    try {
                        if (mediaPlayer?.isPlaying != true) {
                            Log.d(TAG, "Media player not playing, restarting")
                            playAlarmSound(soundId)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in health check", e)
                        // Try to restart on error
                        playAlarmSound(soundId)
                    }

                    // Schedule next check
                    handler.postDelayed(this, 5000) // Check every 5 seconds
                }
            }
        }, 5000) // First check after 5 seconds
    }

    private fun setupVolumeIncrease() {
        // Start with lower volume and gradually increase
        currentVolume = 0.3f
        mediaPlayer?.setVolume(currentVolume, currentVolume)

        volumeIncreaseHandler = Handler(Looper.getMainLooper())
        volumeIncreaseHandler?.postDelayed(object : Runnable {
            override fun run() {
                if (currentVolume < 1.0f) {
                    currentVolume = Math.min(1.0f, currentVolume + 0.1f)
                    mediaPlayer?.setVolume(currentVolume, currentVolume)
                    Log.d(TAG, "Increased volume to: $currentVolume")

                    // Schedule next increase
                    volumeIncreaseHandler?.postDelayed(this, 30000) // Increase every 30 seconds
                }
            }
        }, 30000) // First increase after 30 seconds
    }

    // Add a method to load the volume setting from shared preferences
    private fun loadVolumeSetting() {
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val savedVolume = prefs.getInt("flutter.alarm_volume", -1)
            
            if (savedVolume != -1) {
                // Convert from percentage (0-100) to float (0.0-1.0)
                currentVolume = savedVolume / 100.0f
                Log.d(TAG, "Loaded volume setting from preferences: $savedVolume% ($currentVolume)")
            } else {
                // Default volume if not set
                currentVolume = 0.7f
                Log.d(TAG, "Using default volume: $currentVolume")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading volume setting, using default", e)
            currentVolume = 0.7f
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "Service being destroyed")

        // Release media player with better error handling
        try {
            mediaPlayer?.apply {
                try {
                    if (isPlaying) {
                        stop()
                        Log.d(TAG, "MediaPlayer stopped successfully")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error stopping MediaPlayer", e)
                } finally {
                    try {
                        reset()
                        Log.d(TAG, "MediaPlayer reset successfully")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error resetting MediaPlayer", e)
                    }
                    
                    try {
                        release()
                        Log.d(TAG, "MediaPlayer released successfully")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error releasing MediaPlayer", e)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling MediaPlayer cleanup", e)
        }
        mediaPlayer = null

        // Release audio focus
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let {
                    val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    audioManager.abandonAudioFocusRequest(it)
                    Log.d(TAG, "Abandoned audio focus request (API 26+)")
                }
            } else {
                @Suppress("DEPRECATION")
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager.abandonAudioFocus(null)
                Log.d(TAG, "Abandoned audio focus (legacy)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing audio focus", e)
        }
        audioFocusRequest = null

        // Release wake lock
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.d(TAG, "Wake lock released")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing wake lock", e)
        }
        wakeLock = null

        // Cancel volume increase handler
        try {
            volumeIncreaseHandler?.removeCallbacksAndMessages(null)
            Log.d(TAG, "Volume increase handler removed")
        } catch (e: Exception) {
            Log.e(TAG, "Error removing volume handlers", e)
        }
        volumeIncreaseHandler = null

        isServiceRunning = false
        Log.d(TAG, "Service marked as not running")

        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    // Static method to check if service is running
    fun isRunning(): Boolean {
        return isServiceRunning
    }
}

