package com.example.flutter_bunny_video_player

import android.content.Context
import androidx.media3.common.util.UnstableApi
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.android.asCoroutineDispatcher
import android.os.Handler
import android.os.Looper
import net.bunny.bunnystreamplayer.download.BunnyDownloadError
import net.bunny.bunnystreamplayer.download.BunnyDownloadManagerProvider
import net.bunny.bunnystreamplayer.download.BunnyDownloadProgress
import net.bunny.bunnystreamplayer.download.BunnyDownloadState
import net.bunny.bunnystreamplayer.download.BunnyOfflineManager

/**
 * Bridges the offline download API onto Flutter.
 *
 * Channel names, method names, payload keys and error codes here are a
 * contract shared byte-for-byte with the iOS plugin. The app layer is one Dart
 * implementation over both; if these two ever drift, that single
 * implementation silently becomes two.
 *
 * Scoped to the plugin rather than a platform view because downloads outlive
 * any player: a per-view channel would stop reporting the moment the student
 * navigated away from the lesson.
 */
@UnstableApi
class BunnyDownloadChannelHandler(
    private val context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "klasio/bunny_video_downloads"
        const val EVENT_CHANNEL = "klasio/bunny_video_downloads/events"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(
        SupervisorJob() + mainHandler.asCoroutineDispatcher("bunny-downloads"),
    )

    private var eventSink: EventChannel.EventSink? = null

    private val progressListener: (BunnyDownloadProgress) -> Unit = { progress ->
        // Platform channels must be touched from the main thread; media3's
        // download callbacks do not promise one.
        mainHandler.post { eventSink?.success(progress.toMap()) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)
            "cancel" -> withCacheKey(call, result) {
                BunnyOfflineManager.cancelDownload(context, it)
                result.success(null)
            }
            "delete" -> withCacheKey(call, result) {
                BunnyOfflineManager.deleteDownload(context, it)
                result.success(null)
            }
            "deleteAll" -> {
                BunnyOfflineManager.deleteAll(context)
                result.success(null)
            }
            "list" -> result.success(
                BunnyOfflineManager.listDownloads(context).map {
                    mapOf("cacheKey" to it.cacheKey, "sizeBytes" to it.bytesDownloaded)
                },
            )
            "get" -> withCacheKey(call, result) { key ->
                val entry = BunnyOfflineManager.listDownloads(context)
                    .firstOrNull { it.cacheKey == key }
                result.success(
                    entry?.let {
                        mapOf("cacheKey" to it.cacheKey, "sizeBytes" to it.bytesDownloaded)
                    },
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val cacheKey = call.argument<String>("cacheKey")
        val videoId = call.argument<String>("videoId")
        val libraryId = (call.argument<Number>("libraryId"))?.toLong()

        if (cacheKey.isNullOrEmpty() || videoId.isNullOrEmpty() || libraryId == null) {
            result.error("not_found", "cacheKey, videoId and libraryId are required", null)
            return
        }

        // Applied before enqueueing so the very first download honours the
        // preference rather than picking it up on the next one.
        BunnyDownloadManagerProvider.setWifiOnly(
            context,
            call.argument<Boolean>("wifiOnly") ?: true,
        )

        BunnyOfflineManager.startDownload(
            context = context,
            scope = scope,
            cacheKey = cacheKey,
            videoId = videoId,
            libraryId = libraryId,
            token = call.argument<String>("token"),
            expires = (call.argument<Number>("expires"))?.toLong(),
            referer = call.argument<String>("referer"),
            title = call.argument<String>("title"),
        ) { accepted, error ->
            if (accepted) {
                result.success(null)
            } else {
                result.error(error.toCode(), "Download could not be started", null)
            }
        }
    }

    private inline fun withCacheKey(
        call: MethodCall,
        result: MethodChannel.Result,
        body: (String) -> Unit,
    ) {
        val cacheKey = call.argument<String>("cacheKey")
        if (cacheKey.isNullOrEmpty()) {
            result.error("not_found", "cacheKey is required", null)
            return
        }
        body(cacheKey)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        BunnyOfflineManager.addProgressListener(progressListener)
    }

    override fun onCancel(arguments: Any?) {
        BunnyOfflineManager.removeProgressListener(progressListener)
        eventSink = null
    }

    private fun BunnyDownloadProgress.toMap(): Map<String, Any?> = mapOf(
        "cacheKey" to cacheKey,
        "status" to state.toWireName(),
        "progress" to progress.toDouble(),
        "sizeBytes" to bytesDownloaded,
        "errorCode" to error.toCode(),
    )

    private fun BunnyDownloadState.toWireName(): String = when (this) {
        BunnyDownloadState.QUEUED -> "queued"
        BunnyDownloadState.DOWNLOADING -> "downloading"
        BunnyDownloadState.DOWNLOADED -> "downloaded"
        BunnyDownloadState.FAILED -> "failed"
        BunnyDownloadState.CANCELLED -> "cancelled"
    }

    private fun BunnyDownloadError?.toCode(): String = when (this) {
        BunnyDownloadError.NETWORK -> "network"
        BunnyDownloadError.STORAGE_FULL -> "storage_full"
        BunnyDownloadError.UNAUTHORIZED -> "unauthorized"
        BunnyDownloadError.NOT_FOUND -> "not_found"
        BunnyDownloadError.UNKNOWN, null -> "unknown"
    }
}
