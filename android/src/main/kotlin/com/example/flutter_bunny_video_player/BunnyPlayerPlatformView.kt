package com.example.flutter_bunny_video_player

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.graphics.PorterDuff
import android.graphics.drawable.Drawable
import android.util.Log
import android.view.ContextThemeWrapper
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.activity.ComponentActivity
import androidx.annotation.ColorInt
import androidx.annotation.DrawableRes
import androidx.appcompat.content.res.AppCompatResources
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.ComposeView
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.DrawableCompat
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import androidx.lifecycle.Lifecycle
import net.bunny.api.BunnyStreamApi
import net.bunny.bunnystreamplayer.model.PlayerIconSet
import net.bunny.bunnystreamplayer.ui.BunnyStreamPlayer
import kotlin.math.exp

@SuppressLint("UnusedMaterial3ScaffoldPaddingParameter", "ResourceAsColor")
class BunnyVideoPlatformView(
    context: Context,
    creationParams: Map<String, Any>?,
) : PlatformView {

    private val rootView: View

    init {
        val wrappedContext = ContextThemeWrapper(context, androidx.appcompat.R.style.Theme_AppCompat_NoActionBar)
        // Extract creation params
        val videoId = creationParams?.get("videoId") as? String
        val accessKey = creationParams?.get("accessKey") as? String ?: ""
        val libraryId = (creationParams?.get("libraryId") as? Number)?.toLong() ?: 0L
        val token = (creationParams?.get("token") as? String)
        val expire = (creationParams?.get("expire") as? Number)?.toLong()
        val playIconAsset = creationParams?.get("playIconAsset") as? String
        val referer = creationParams?.get("referer") as? String
        val isPortrait= creationParams?.get("isPortrait") as? Boolean
        val isScreenShotProtectEnable = creationParams?.get("isScreenShotProtectEnable") as? Boolean
        // Passing this through is what makes offline playback work at all: the
        // SDK reads the encrypted cache when the key is fully downloaded, and
        // falls back to stored metadata when the network is gone. Dropping it
        // here silently turned every play into a streaming play.
        val cacheKey = creationParams?.get("cacheKey") as? String
        rootView = LayoutInflater.from(wrappedContext)
            .inflate(R.layout.activity_flutter_bunny_video, null)

        BunnyStreamApi.initialize(context, accessKey, libraryId)

        val videoPlayer = rootView.findViewById<BunnyStreamPlayer>(R.id.videoPlayer)
        videoPlayer.iconSet = PlayerIconSet(
            rewindIcon = R.drawable.ic_replay,
            forwardIcon = R.drawable.ic_forward,
            settingsIcon = R.drawable.ic_setting,
            fullscreenOnIcon = R.drawable.ic_fullscreen,
            fullscreenOffIcon = R.drawable.ic_fullscreen_exit,
        )
        if(token==null && expire==null){
            videoPlayer.playVideo(
                videoId = videoId!!,
                libraryId = libraryId,
                videoTitle = "",
                refererValue = referer,
                cacheKey = cacheKey,
            )
        }else{
            videoPlayer.playVideoWithToken(
                videoId = videoId!!,
                token = token,
                expires = expire,
                libraryId = libraryId,
                videoTitle = "",
                refererValue =referer,
                isPortrait = isPortrait!!,
                isScreenshotProtectionEnabled = isScreenShotProtectEnable!!,
                cacheKey = cacheKey,
            );
        }
        //
    }
    fun getTintedDrawable(
        context: Context,
        @DrawableRes drawableRes: Int,
        @ColorInt color: Int
    ): Drawable? {
        val drawable = ContextCompat.getDrawable(context, drawableRes) ?: return null
        val wrappedDrawable = DrawableCompat.wrap(drawable).mutate()
        DrawableCompat.setTint(wrappedDrawable, color)
        return wrappedDrawable
    }
    override fun getView(): View = rootView
    fun getActivityFromContext(context: Context): Activity? {
        var ctx = context
        while (ctx is ContextWrapper) {
            if (ctx is Activity) return ctx
            ctx = ctx.baseContext
        }
        return null
    }
    override fun dispose() {

    }
}