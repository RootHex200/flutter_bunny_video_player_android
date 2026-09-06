import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bunny_video_player/flutter_bunny_video_player.dart';

// Demo video credentials.
const _videoId = "1e5b2551-adde-4ee9-b5b3-876c58ebfd33";
const _libraryId = 316762;
const _expire = 20250922120000;
const _token = "db6ba6794ebdccedfc9e7719ce6eb4e8700b2ee4b0159fb3b8b311fd99ade91f";
const _referer = "https://sabitur.klasio.dev";

// One download per video: the cache key is just the video id here. A host
// app can use any unique string (e.g. "<userId>/<videoId>").
const _cacheKey = _videoId;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: DownloadDemoPage());
  }
}

class DownloadDemoPage extends StatefulWidget {
  const DownloadDemoPage({super.key});

  @override
  State<DownloadDemoPage> createState() => _DownloadDemoPageState();
}

class _DownloadDemoPageState extends State<DownloadDemoPage> {
  StreamSubscription<BunnyDownloadEvent>? _sub;

  BunnyDownloadStatus? _status;
  double _progress = 0;
  String? _errorCode;
  List<BunnyOfflineVideo> _downloaded = const [];

  // When true the player below plays from the downloaded copy, no network.
  bool _playOffline = false;

  @override
  void initState() {
    super.initState();
    _sub = BunnyVideoDownloads.events().listen(_onEvent);
    _refreshList();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(BunnyDownloadEvent event) {
    if (event.cacheKey != _cacheKey) return;
    setState(() {
      _status = event.status;
      _progress = event.progress;
      _errorCode = event.errorCode;
    });
    if (event.status == BunnyDownloadStatus.downloaded) _refreshList();
  }

  Future<void> _refreshList() async {
    final list = await BunnyVideoDownloads.list();
    if (!mounted) return;
    setState(() => _downloaded = list);
  }

  Future<void> _start() async {
    setState(() {
      _status = BunnyDownloadStatus.queued;
      _progress = 0;
      _errorCode = null;
    });
    try {
      await BunnyVideoDownloads.start(
        cacheKey: _cacheKey,
        videoId: _videoId,
        libraryId: _libraryId,
        token: _token,
        expires: _expire,
        referer: _referer,
        title: 'Demo video',
        wifiOnly: false,
      );
    } on PlatformException catch (e) {
      // e.g. `unauthorized` when the library has DRM enabled — the native
      // side refuses to download DRM-protected videos.
      if (!mounted) return;
      setState(() {
        _status = BunnyDownloadStatus.failed;
        _errorCode = e.code;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: ${e.code} — ${e.message}')),
      );
    }
  }

  Future<void> _cancel() => BunnyVideoDownloads.cancel(_cacheKey);

  Future<void> _delete() async {
    await BunnyVideoDownloads.delete(_cacheKey);
    setState(() {
      _status = null;
      _progress = 0;
      _playOffline = false;
    });
    await _refreshList();
  }

  bool get _isDownloaded =>
      _downloaded.any((v) => v.cacheKey == _cacheKey) ||
      _status == BunnyDownloadStatus.downloaded;

  bool get _isBusy =>
      _status == BunnyDownloadStatus.queued ||
      _status == BunnyDownloadStatus.downloading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_playOffline ? 'Playing offline' : 'Playing online'),
      ),
      body: ListView(
        children: [
          SizedBox(
            height: 300,
            child: BunnyPlayerView(
              // Recreate the platform view when the source mode flips.
              key: ValueKey(_playOffline),
              accessKey: null,
              videoId: _videoId,
              libraryId: _libraryId,
              expire: _expire,
              token: _token,
              referer: _referer,
              isPortrait: true,
              cacheKey: _cacheKey,
              offline: _playOffline,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DownloadStatusTile(
                  status: _status,
                  progress: _progress,
                  errorCode: _errorCode,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isBusy || _isDownloaded ? null : _start,
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? _cancel : null,
                        icon: const Icon(Icons.close),
                        label: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isDownloaded ? _delete : null,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Play offline'),
                  subtitle: const Text(
                    'Play the downloaded copy without touching the network',
                  ),
                  value: _playOffline,
                  onChanged: _isDownloaded
                      ? (v) => setState(() => _playOffline = v)
                      : null,
                ),
                const Divider(),
                Text(
                  'Downloaded videos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_downloaded.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Nothing downloaded yet.'),
                  ),
                for (final video in _downloaded)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle, color: Colors.green),
                    title: Text(video.cacheKey),
                    subtitle: Text(_formatBytes(video.sizeBytes)),
                  ),
                if (_downloaded.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      await BunnyVideoDownloads.deleteAll();
                      setState(() {
                        _status = null;
                        _progress = 0;
                        _playOffline = false;
                      });
                      await _refreshList();
                    },
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Delete all'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadStatusTile extends StatelessWidget {
  const _DownloadStatusTile({
    required this.status,
    required this.progress,
    required this.errorCode,
  });

  final BunnyDownloadStatus? status;
  final double progress;
  final String? errorCode;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      null => 'Not downloaded',
      BunnyDownloadStatus.queued => 'Queued…',
      BunnyDownloadStatus.downloading =>
        progress >= 0
            ? 'Downloading ${(progress * 100).toStringAsFixed(0)}%'
            : 'Downloading…',
      BunnyDownloadStatus.downloaded => 'Downloaded — available offline',
      BunnyDownloadStatus.failed => 'Failed (${errorCode ?? 'unknown'})',
      BunnyDownloadStatus.cancelled => 'Cancelled',
    };

    final showBar = status == BunnyDownloadStatus.queued ||
        status == BunnyDownloadStatus.downloading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        if (showBar) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress >= 0 ? progress : null),
        ],
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes >= 1 << 30) {
    return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1 << 20) {
    return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
  return '$bytes B';
}
