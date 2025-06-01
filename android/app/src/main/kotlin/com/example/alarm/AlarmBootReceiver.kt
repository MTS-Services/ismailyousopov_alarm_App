package com.example.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.app.NotificationManager
import android.util.Log

@Suppress("unused")
class AlarmBootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "AlarmBootReceiver"
        private var mediaPlayer: MediaPlayer? = null
        private var isCurrentlyActive = false
        private var audioFocusRequest: AudioFocusRequest? = null


        fun stopAlarmSound(context: Context) {
            isCurrentlyActive = false


            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
                audioFocusRequest?.let { request ->
                    audioManager?.abandonAudioFocusRequest(request)
                }
                audioFocusRequest = null
            }

            mediaPlayer?.apply {
                if (isPlaying) {
                    stop()
                }
                release()
                mediaPlayer = null
            }

            Log.d(TAG, "Alarm sound stopped")
        }
    }



    private fun clearExistingNotifications(context: Context) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
            Log.d(TAG, "Cleared all existing notifications")
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing notifications", e)
        }
    }


    override fun onReceive(context: Context, intent: Intent) {

        clearExistingNotifications(context)
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON" ||
            intent.action == "com.htc.intent.action.QUICKBOOT_POWERON") {

            Log.d(TAG, "Device booted, restoring alarms")

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = "com.example.alarm.RESTORE_ALARMS"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra("fromBoot", true)
            }

            context.startActivity(launchIntent)
            restoreActiveAlarm(context)
        }
    }


    private fun restoreActiveAlarm(context: Context) {
        try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            val activeAlarmId = prefs.getInt("flutter.active_alarm_id", -1)
            val activeSoundId = prefs.getInt("flutter.active_alarm_sound", 1)
            val alarmStartTime = prefs.getInt("flutter.alarm_start_time", 0)
            val now = System.currentTimeMillis()

            if (activeAlarmId != -1) {
                val alarmAge = now - alarmStartTime

                if (alarmAge < 30 * 60 * 1000) {
                    val intent = Intent(context, AlarmReceiver::class.java).apply {
                        action = "com.example.alarm.ALARM_TRIGGERED"
                        putExtra("alarmId", activeAlarmId)
                        putExtra("soundId", activeSoundId)
                    }
                    context.sendBroadcast(intent)
                    Log.d(TAG, "Restored active alarm: $activeAlarmId")
                }
            }

            val scheduledAlarmsString = prefs.getString("flutter.scheduled_alarms", null)
            if (!scheduledAlarmsString.isNullOrEmpty()) {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager

                try {
                    // Handle different formats
                    val alarmsList = if (scheduledAlarmsString.startsWith("[") && scheduledAlarmsString.endsWith("]")) {
                        // It's a JSON array
                        try {
                            val jsonArray = org.json.JSONArray(scheduledAlarmsString)
                            List(jsonArray.length()) { i -> jsonArray.getString(i) }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error parsing JSON alarm data", e)
                            scheduledAlarmsString.split(",")
                        }
                    } else {
                        // Simple comma-separated list
                        scheduledAlarmsString.split(",")
                    }

                    for (alarmInfo in alarmsList) {
                        if (alarmInfo.isEmpty()) continue

                        // Clean up the alarm info string
                        val cleanInfo = alarmInfo.trim()
                            .replace("[", "")
                            .replace("]", "")
                            .replace("\"", "")

                        val parts = cleanInfo.split(":")
                        if (parts.size >= 3) {
                            val id = parts[0].toIntOrNull() ?: continue
                            val soundId = parts[1].toIntOrNull() ?: 1
                            val scheduledTime = parts[2].toLongOrNull() ?: continue
                            val nfcRequired = parts.getOrNull(3)?.toBoolean() ?: false

                            // Only restore future alarms
                            if (scheduledTime > now) {
                                val intent = Intent(context, AlarmReceiver::class.java).apply {
                                    action = "com.example.alarm.ALARM_TRIGGERED"
                                    putExtra("alarmId", id)
                                    putExtra("soundId", soundId)
                                    putExtra("nfcRequired", nfcRequired)
                                }

                                // Use the exact scheduled time without any adjustment for precise timing
                                val exactScheduledTime = scheduledTime

                                val pendingIntent = android.app.PendingIntent.getBroadcast(
                                    context,
                                    id,
                                    intent,
                                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)

                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                    alarmManager.setExactAndAllowWhileIdle(android.app.AlarmManager.RTC_WAKEUP, exactScheduledTime, pendingIntent)
                                } else {
                                    alarmManager.setExact(android.app.AlarmManager.RTC_WAKEUP, exactScheduledTime, pendingIntent)
                                }

                                Log.d(TAG, "Restored scheduled alarm: $id for exact time: $exactScheduledTime (original: $scheduledTime)")
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error processing scheduled alarms", e)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error restoring alarms", e)
        }
    }

}
