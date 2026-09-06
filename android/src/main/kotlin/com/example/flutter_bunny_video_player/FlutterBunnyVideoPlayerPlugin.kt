package com.example.flutter_bunny_video_player

import androidx.activity.ComponentActivity
import androidx.annotation.NonNull

import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
/** FlutterBunnyVideoPlayerPlugin */
@UnstableApi
class FlutterBunnyVideoPlayerPlugin: FlutterPlugin, ActivityAware { // Implement ActivityAware
  private var downloadMethodChannel: MethodChannel? = null
  private var downloadEventChannel: EventChannel? = null
  private var downloadHandler: BunnyDownloadChannelHandler? = null
  private var activity: ComponentActivity? = null // To hold a reference to the host activity

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    flutterPluginBinding
      .platformViewRegistry
      .registerViewFactory(
        "bunny_player_view",
        BunnyPlayerViewFactory()
      )

    // Engine-scoped, not view-scoped: a download outlives the player view that
    // started it, so a per-view channel would stop reporting the moment the
    // student left the lesson.
    val handler = BunnyDownloadChannelHandler(flutterPluginBinding.applicationContext)
    downloadHandler = handler

    downloadMethodChannel = MethodChannel(
      flutterPluginBinding.binaryMessenger,
      BunnyDownloadChannelHandler.METHOD_CHANNEL
    ).apply { setMethodCallHandler(handler) }

    downloadEventChannel = EventChannel(
      flutterPluginBinding.binaryMessenger,
      BunnyDownloadChannelHandler.EVENT_CHANNEL
    ).apply { setStreamHandler(handler) }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    downloadMethodChannel?.setMethodCallHandler(null)
    downloadMethodChannel = null
    downloadEventChannel?.setStreamHandler(null)
    downloadEventChannel = null
    downloadHandler = null
  }

  // --- ActivityAware methods ---
  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    // Cast to ComponentActivity to ensure it implements LifecycleOwner and SavedStateRegistryOwner
    if (binding.activity is ComponentActivity) {
      activity = binding.activity as ComponentActivity
    } else {
      // Handle cases where the host activity might not be a ComponentActivity
      // This is less common in modern Android/Flutter setups, but possible.
      // You might need to find a different way to get a LifecycleOwner.
      // For most cases, Flutter's default Activity will be a ComponentActivity.
      println("Warning: Host activity is not a ComponentActivity. ViewTreeLifecycleOwner might not be set correctly.")
    }
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    if (binding.activity is ComponentActivity) {
      activity = binding.activity as ComponentActivity
    }
  }

  override fun onDetachedFromActivity() {
    activity = null
  }
}

