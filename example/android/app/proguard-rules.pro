# Flutter specific rules.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.embedding.**  { *; }

# Rules for the plugin
-keep class com.example.flutter_bunny_video_player.** { *; }

# Keep rules for support library classes
-keep class android.support.v4.media.** { *; }
-keep class android.support.v4.media.session.** { *; }

# Keep this to avoid a NullPointerException in release builds
-keep class com.google.android.exoplayer2.ui.PlayerNotificationManager$NotificationBroadcastReceiver { *; }
-keep class androidx.media.** { *; }