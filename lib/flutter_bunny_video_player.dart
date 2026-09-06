import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

class BunnyPlayerView extends StatefulWidget {
  final String? accessKey;
  final String videoId;
  final int libraryId;
  final String? token;
  final int? expire;
  final String? referer;
  final bool isPortrait;
  final bool isScreenShotProtectEnable;

  /// Identifies downloaded content for this video. Pass the same key the
  /// download was started with. Only consulted when [offline] is true.
  final String? cacheKey;

  /// Play from the downloaded copy instead of streaming. Requires [cacheKey],
  /// and that key to have finished downloading — the native player then reads
  /// the encrypted store and needs no network.
  ///
  /// Left false, playback streams over HTTP and ignores [cacheKey] entirely.
  /// That is deliberate: routing a streaming play through the download cache
  /// can surface bytes from an interrupted download.
  final bool offline;

  const BunnyPlayerView({
    super.key,
    required this.accessKey,
    required this.videoId,
    required this.libraryId,
    this.token,
    this.referer,
    this.expire,
    this.isPortrait = false,
    this.isScreenShotProtectEnable = false,
    this.cacheKey,
    this.offline = false,
  });

  @override
  State<BunnyPlayerView> createState() => _BunnyPlayerViewState();
}

class _BunnyPlayerViewState extends State<BunnyPlayerView> {
  @override
  void initState() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    const viewType = 'bunny_player_view';

    if (Platform.isAndroid) {
      return BunnyStreamAndroidPlatformView(
        viewType: viewType,
        accessKey: widget.accessKey,
        videoId: widget.videoId,
        libraryId: widget.libraryId,
        token: widget.token,
        expire: widget.expire,
        referer: widget.referer,
        isPortrait: widget.isPortrait,
        isScreenShotProtectEnable: widget.isScreenShotProtectEnable,
        cacheKey: widget.cacheKey,
        offline: widget.offline,
      );
    }
    return const SizedBox();
  }
}

class BunnyStreamAndroidPlatformView extends StatelessWidget {
  final String viewType;
  final String? accessKey;
  final String videoId;
  final int libraryId;
  final String? token;
  final int? expire;
  final String? referer;
  final bool isPortrait;
  final bool isScreenShotProtectEnable;
  final String? cacheKey;
  final bool offline;
  const BunnyStreamAndroidPlatformView({
    super.key,
    required this.viewType,
    required this.videoId,
    required this.libraryId,
    this.accessKey,
    this.token,
    this.expire,
    this.referer,
    required this.isPortrait,
    required this.isScreenShotProtectEnable,
    this.cacheKey,
    this.offline = false,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> creationParams = {
      'accessKey': accessKey,
      'videoId': videoId,
      'libraryId': libraryId,
      'token': token,
      'expire': expire,
      'referer': referer,
      'isPortrait': isPortrait,
      'isScreenShotProtectEnable': isScreenShotProtectEnable,
      'cacheKey': cacheKey,
      'offline': offline,
    };

    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (PlatformViewCreationParams params) {
        return PlatformViewsService.initSurfaceAndroidView(
          id: params.id,
          viewType: viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
      },
    );
  }
}

/// Where a download stands, as the native engine reports it.
enum BunnyDownloadStatus { queued, downloading, downloaded, failed, cancelled }

/// One progress or terminal event for a download.
class BunnyDownloadEvent {
  const BunnyDownloadEvent({
    required this.cacheKey,
    required this.status,
    this.progress = 0,
    this.sizeBytes = 0,
    this.errorCode,
  });

  final String cacheKey;
  final BunnyDownloadStatus status;

  /// 0..1, or -1 when the native layer knows bytes but not the total.
  final double progress;

  final int sizeBytes;

  /// One of `network`, `storage_full`, `unauthorized`, `not_found`,
  /// `unknown`. Set only when [status] is [BunnyDownloadStatus.failed].
  final String? errorCode;

  static BunnyDownloadEvent? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final cacheKey = raw['cacheKey'];
    final status = _statusFrom(raw['status']);
    if (cacheKey is! String || cacheKey.isEmpty || status == null) return null;

    return BunnyDownloadEvent(
      cacheKey: cacheKey,
      status: status,
      progress: (raw['progress'] as num?)?.toDouble() ?? 0,
      sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
      errorCode: raw['errorCode'] as String?,
    );
  }

  static BunnyDownloadStatus? _statusFrom(dynamic raw) => switch (raw) {
    'queued' => BunnyDownloadStatus.queued,
    'downloading' => BunnyDownloadStatus.downloading,
    'downloaded' => BunnyDownloadStatus.downloaded,
    'failed' => BunnyDownloadStatus.failed,
    'cancelled' => BunnyDownloadStatus.cancelled,
    _ => null,
  };
}

/// One completed download held by the native store.
class BunnyOfflineVideo {
  const BunnyOfflineVideo({required this.cacheKey, required this.sizeBytes});

  final String cacheKey;
  final int sizeBytes;
}

/// Offline downloads for Bunny Stream video.
///
/// Channel names and payload shapes match the iOS plugin exactly, so a host
/// app can drive both platforms through one implementation.
class BunnyVideoDownloads {
  BunnyVideoDownloads._();

  static const MethodChannel _method = MethodChannel(
    'klasio/bunny_video_downloads',
  );
  static const EventChannel _events = EventChannel(
    'klasio/bunny_video_downloads/events',
  );

  static Stream<BunnyDownloadEvent>? _stream;

  /// Starts downloading a video for offline playback.
  ///
  /// Resolves Bunny's play-config natively and captures it alongside the
  /// media, so playback later needs no network.
  static Future<void> start({
    required String cacheKey,
    required String videoId,
    required int libraryId,
    String? token,
    int? expires,
    String? referer,
    String? title,
    bool wifiOnly = true,
  }) {
    return _method.invokeMethod<void>('start', <String, dynamic>{
      'cacheKey': cacheKey,
      'videoId': videoId,
      'libraryId': libraryId,
      'token': token,
      'expires': expires,
      'referer': referer,
      'title': title,
      'wifiOnly': wifiOnly,
    });
  }

  static Future<void> cancel(String cacheKey) =>
      _method.invokeMethod<void>('cancel', {'cacheKey': cacheKey});

  static Future<void> delete(String cacheKey) =>
      _method.invokeMethod<void>('delete', {'cacheKey': cacheKey});

  /// Drops every download. Used by a host app's logout wipe.
  static Future<void> deleteAll() => _method.invokeMethod<void>('deleteAll');

  static Future<List<BunnyOfflineVideo>> list() async {
    final raw = await _method.invokeMethod<List<dynamic>>('list');
    if (raw == null) return const [];

    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (e) => BunnyOfflineVideo(
            cacheKey: e['cacheKey'] as String? ?? '',
            sizeBytes: (e['sizeBytes'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((e) => e.cacheKey.isNotEmpty)
        .toList(growable: false);
  }

  /// Progress and terminal events for every download, keyed by cache key.
  ///
  /// One broadcast subscription for the app's lifetime — downloads outlive any
  /// screen, so re-listening per widget would drop events between screens.
  static Stream<BunnyDownloadEvent> events() {
    return _stream ??= _events
        .receiveBroadcastStream()
        .map(BunnyDownloadEvent.fromMap)
        .where((e) => e != null)
        .cast<BunnyDownloadEvent>()
        .asBroadcastStream();
  }
}
