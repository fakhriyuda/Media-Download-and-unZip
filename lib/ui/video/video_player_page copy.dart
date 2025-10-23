// fullscreen_video_player.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// FullscreenVideoPlayer
/// - Accepts either a single [filePath] or a list of [filePaths].
/// - Plays the current file, auto-advances to next on end, supports prev/next/play/pause.
/// - Forces landscape immersive mode while visible and restores UI/orientation on pop.
/// - Handles basic errors and skips missing/corrupted files.
class FullscreenVideoPlayer extends StatefulWidget {
  /// Either provide [filePath] (single) or [filePaths] (playlist). If both are
  /// provided, [filePaths] takes precedence.
  final String? filePath;
  final List<String>? filePaths;

  /// Start index for playlist (default 0)
  final int startIndex;

  /// If true, player loops when reaching the last item
  final bool loopPlaylist;

  const FullscreenVideoPlayer({
    this.filePath,
    this.filePaths,
    this.startIndex = 0,
    this.loopPlaylist = false,
    super.key,
  }) : assert(
         filePath != null || filePaths != null,
         'Provide filePath or filePaths',
       );

  @override
  State<FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<FullscreenVideoPlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  int _index = 0; // index in the playlist
  List<String> _paths = [];
  bool _isSeeking = false;
  String? _errorMsg;

  String get _currentPath => _paths[_index];

  @override
  void initState() {
    super.initState();
    // Build playlist
    if (widget.filePaths != null) {
      _paths = List<String>.from(widget.filePaths!);
    } else if (widget.filePath != null) {
      _paths = [widget.filePath!];
    }
    _index = widget.startIndex.clamp(0, _paths.length - 1);

    // Force landscape + immersive
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Initialize first playable file
    _initAndPlay(_index);
  }

  Future<void> _initAndPlay(int index) async {
    if (index < 0 || index >= _paths.length) return;
    _isSeeking = true;
    _errorMsg = null;
    setState(() {
      _ready = false;
    });

    // dispose old controller
    try {
      await _controller?.pause();
      await _controller?.dispose();
    } catch (_) {}

    final path = _paths[index];
    final file = File(path);
    if (!await file.exists()) {
      _errorMsg = 'File not found:\n$path';
      // try next
      final next = await _nextIndex(index);
      if (next != null && next != index) {
        _initAndPlay(next);
        return;
      }
      setState(() {});
      _isSeeking = false;
      return;
    }

    final ctrl = VideoPlayerController.file(file);
    _controller = ctrl;

    try {
      await ctrl.initialize();
      if (!mounted) return;
      ctrl.setLooping(false);
      ctrl.addListener(_playerListener);
      await ctrl.play();

      setState(() {
        _ready = true;
        _index = index;
        _errorMsg = null;
      });
    } catch (e) {
      _errorMsg = 'Failed to open file:\n$path';
      // try next
      final next = await _nextIndex(index);
      if (next != null && next != index) {
        _initAndPlay(next);
        return;
      }
      setState(() {});
    } finally {
      _isSeeking = false;
    }
  }

  void _playerListener() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    final pos = c.value.position;
    final dur = c.value.duration;
    if (dur != null && pos >= dur - const Duration(milliseconds: 250)) {
      // near end -> advance
      if (!_isSeeking) {
        _next();
      }
    }
  }

  Future<int?> _nextIndex(int from) async {
    final next = from + 1;
    if (next < _paths.length) return next;
    if (widget.loopPlaylist && _paths.isNotEmpty) return 0;
    return null;
  }

  Future<int?> _prevIndex(int from) async {
    final prev = from - 1;
    if (prev >= 0) return prev;
    if (widget.loopPlaylist && _paths.isNotEmpty) return _paths.length - 1;
    return null;
  }

  void _next() async {
    if (_isSeeking) return;
    final n = await _nextIndex(_index);
    if (n != null) _initAndPlay(n);
  }

  void _prev() async {
    if (_isSeeking) return;
    final p = await _prevIndex(_index);
    if (p != null) _initAndPlay(p);
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_playerListener);
    _controller?.pause();
    _controller?.dispose();

    // restore UI & orientation
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            // video / loading / error
            Center(
              child:
                  _errorMsg != null
                      ? _buildError()
                      : _ready && c != null
                      ? AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: VideoPlayer(c),
                      )
                      : const CircularProgressIndicator(),
            ),

            // top bar: back + title
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _paths.isNotEmpty
                          ? _paths[_index].split('/').last
                          : 'No video',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_index + 1} / ${_paths.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // bottom controls
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_ready && c != null)
                    VideoProgressIndicator(c, allowScrubbing: true),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.skip_previous,
                          color: Colors.white,
                        ),
                        onPressed: _paths.length > 1 ? _prev : null,
                      ),
                      const SizedBox(width: 12),
                      FloatingActionButton(
                        backgroundColor: Colors.black54,
                        onPressed: _togglePlay,
                        child: Icon(
                          (c != null && c.value.isPlaying)
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white),
                        onPressed: _paths.length > 1 ? _next : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.error_outline, color: Colors.white, size: 48),
      const SizedBox(height: 8),
      Text(
        _errorMsg ?? 'Unknown error',
        style: const TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      ElevatedButton.icon(
        icon: const Icon(Icons.skip_next),
        label: const Text('Skip to next'),
        onPressed: () async {
          final n = await _nextIndex(_index);
          if (n != null) _initAndPlay(n);
        },
      ),
    ],
  );
}
