package dev.brepsight.cad_engine

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import java.util.concurrent.ConcurrentHashMap

object ModelTaskCancellationRegistry {
    private val requested = ConcurrentHashMap.newKeySet<String>()

    fun request(taskId: String) {
        if (taskId.isNotBlank()) requested.add(taskId)
    }

    fun consume(taskId: String): Boolean = requested.remove(taskId)

    fun clear(taskId: String) {
        requested.remove(taskId)
    }
}

class ModelTaskService : Service() {
    companion object {
        const val ACTION_START = "dev.brepsight.cad_engine.task.START"
        const val ACTION_UPDATE = "dev.brepsight.cad_engine.task.UPDATE"
        const val ACTION_FINISH = "dev.brepsight.cad_engine.task.FINISH"
        const val ACTION_CANCEL = "dev.brepsight.cad_engine.task.CANCEL"

        const val EXTRA_TASK_ID = "taskId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_STAGE = "stage"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_MESSAGE = "message"
        const val EXTRA_SUCCESS = "success"

        private const val CHANNEL_ID = "brepsight_model_processing"
        private const val FOREGROUND_NOTIFICATION_ID = 7301

        fun intent(
            context: Context,
            action: String,
            taskId: String,
            title: String = "BrepSight",
            stage: String = "Preparing",
            progress: Int = 0,
            message: String = "",
            success: Boolean = true,
        ): Intent = Intent(context, ModelTaskService::class.java).apply {
            this.action = action
            putExtra(EXTRA_TASK_ID, taskId)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_STAGE, stage)
            putExtra(EXTRA_PROGRESS, progress.coerceIn(0, 100))
            putExtra(EXTRA_MESSAGE, message)
            putExtra(EXTRA_SUCCESS, success)
        }
    }

    private var activeTaskId: String? = null
    private var activeTitle: String = "BrepSight model task"

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) return START_NOT_STICKY

        val taskId = intent.getStringExtra(EXTRA_TASK_ID).orEmpty()
        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty().ifBlank { "BrepSight model task" }
        val stage = intent.getStringExtra(EXTRA_STAGE).orEmpty().ifBlank { "Working" }
        val progress = intent.getIntExtra(EXTRA_PROGRESS, 0).coerceIn(0, 100)
        val message = intent.getStringExtra(EXTRA_MESSAGE).orEmpty()

        when (intent.action) {
            ACTION_START -> {
                activeTaskId = taskId
                activeTitle = title
                ModelTaskCancellationRegistry.clear(taskId)
                val notification = buildNotification(taskId, title, stage, progress, message, true)
                if (Build.VERSION.SDK_INT >= 29) {
                    startForeground(
                        FOREGROUND_NOTIFICATION_ID,
                        notification,
                        if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0,
                    )
                } else {
                    startForeground(FOREGROUND_NOTIFICATION_ID, notification)
                }
            }

            ACTION_UPDATE -> {
                if (taskId == activeTaskId) {
                    notificationManager().notify(
                        FOREGROUND_NOTIFICATION_ID,
                        buildNotification(taskId, title, stage, progress, message, true),
                    )
                }
            }

            ACTION_CANCEL -> {
                if (taskId.isNotBlank()) ModelTaskCancellationRegistry.request(taskId)
                if (taskId == activeTaskId) {
                    notificationManager().notify(
                        FOREGROUND_NOTIFICATION_ID,
                        buildNotification(taskId, activeTitle, "Cancelling", progress, "Waiting for a safe checkpoint…", false),
                    )
                }
            }

            ACTION_FINISH -> {
                if (taskId == activeTaskId) {
                    val success = intent.getBooleanExtra(EXTRA_SUCCESS, true)
                    notificationManager().notify(
                        FOREGROUND_NOTIFICATION_ID,
                        buildNotification(
                            taskId,
                            title,
                            if (success) "Completed" else "Stopped",
                            if (success) 100 else progress,
                            message,
                            false,
                        ),
                    )
                    activeTaskId = null
                    stopForeground(STOP_FOREGROUND_DETACH)
                    stopSelf()
                }
            }
        }

        return START_NOT_STICKY
    }

    private fun buildNotification(
        taskId: String,
        title: String,
        stage: String,
        progress: Int,
        message: String,
        ongoing: Boolean,
    ): Notification {
        val cancelIntent = PendingIntent.getService(
            this,
            taskId.hashCode(),
            intent(this, ACTION_CANCEL, taskId, title, stage, progress),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(if (message.isBlank()) "$stage · $progress%" else "$stage · $progress% · $message")
            .setSubText("BrepSight engineering task")
            .setOnlyAlertOnce(true)
            .setOngoing(ongoing)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setProgress(100, progress, false)

        if (ongoing) {
            builder.addAction(
                Notification.Action.Builder(
                    null,
                    "Cancel",
                    cancelIntent,
                ).build(),
            )
        }

        applyAndroid16ProgressStyle(builder, progress)
        return builder.build()
    }

    private fun applyAndroid16ProgressStyle(builder: Notification.Builder, progress: Int) {
        if (Build.VERSION.SDK_INT < 36) return
        runCatching {
            val clazz = Class.forName("android.app.Notification\$ProgressStyle")
            val style = clazz.getDeclaredConstructor().newInstance() as Notification.Style
            clazz.getMethod("setProgress", Int::class.javaPrimitiveType).invoke(style, progress)
            builder.setStyle(style)
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Model processing",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Progress and controls for user-initiated long-running engineering model tasks."
            setShowBadge(false)
        }
        notificationManager().createNotificationChannel(channel)
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(NotificationManager::class.java)
}
