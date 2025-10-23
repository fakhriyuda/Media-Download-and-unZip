// fullscreen_video_player.dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'package:yudvatar/model/campaign.dart';
import 'package:yudvatar/model/video_item.dart';
import 'package:yudvatar/ui/video/playlist_page.dart';

/// FullscreenVideoPlayer (updated)
/// - Accepts a default playlist ([defaultPaths]) that plays in loop by default.
/// - Accepts an optional [campaignMap] of friendly campaign names -> list of file paths.
/// - Accepts an optional [campaignNotifier] (ValueNotifier<List<String>?>) used
///   by external code to trigger campaigns programmatically.
/// - Selecting a campaign from the in-player dropdown will play that campaign
///   once, then automatically resume the default looping playlist. The dropdown
///   shows "Default" when no campaign is active.
class FullscreenVideoPlayer extends StatefulWidget {
  /// The default looping playlist (required).
  final List<String> defaultPaths;

  /// Optional map of campaign name -> list of file paths.
  final Map<String, List<String>>? campaignMap;

  /// Notifier used by external UI to request a campaign playlist to be played.
  /// Set its value to a list of file paths to make the player switch to that
  /// playlist. When the campaign is done the notifier value will be cleared
  /// by the player and the default loop will resume.
  final ValueNotifier<List<String>?>? campaignNotifier;

  /// If true, default playlist loops forever.
  final bool loopDefault;

  const FullscreenVideoPlayer({
    required this.defaultPaths,
    this.campaignMap,
    this.campaignNotifier,
    this.loopDefault = true,
    this.videoItems = const [],
    this.campaigns = const [],

    super.key,
  });
  final List<VideoItem> videoItems;
  final List<Campaign> campaigns;

  @override
  State<FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<FullscreenVideoPlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  int _index = 0; // index in the current playlist
  List<String> _paths = [];
  bool _isSeeking = false;
  String? _errorMsg;

  /// currently selected campaign name in dropdown, null = Default
  String? _selectedCampaignName;

  bool _usingDefault = true;
  bool get _isDefault => _usingDefault;
  String get _currentPath => _paths[_index];

  final Dio _dio = Dio();

  final String _campaignUrl =
      'https://vercel-server-universal-link.vercel.app/api/videos/campaign.json';

  int _safeIndexClamp(int desired) {
    if (_paths.isEmpty) return 0;
    // desired might be out of range; clamp safely
    final maxIdx = _paths.length - 1;
    if (desired < 0) return 0;
    if (desired > maxIdx) return maxIdx;
    return desired;
  }

  List<Campaign> campaigns = [];

  List<VideoItem> get _videos => widget.videoItems;
  List<Campaign> get _campaigns => widget.campaigns;
  @override
  void initState() {
    super.initState();
    debugPrint('video items: ${_videos.map((e) => e.videoName).toList()}');
    debugPrint(
      'Campaign items: ${_campaigns.map((e) => e.campaignName).toList()}',
    );
    campaigns = _campaigns;
    // start with default playlist
    _paths = List<String>.from(widget.defaultPaths ?? []);
    _usingDefault = true;
    debugPrint('Default video paths: ${_paths.length} items');
    debugPrint('Default paths: $_paths');
    debugPrint('default map: ${widget.defaultPaths}');
    debugPrint('check _isDefault: $_isDefault');

    if (_paths.isEmpty) {
      // try fallback: first file from campaignMap (if provided)
      final mp = widget.campaignMap;
      if (mp != null && mp.isNotEmpty) {
        final firstPaths = mp.values.firstWhere(
          (l) => l.isNotEmpty,
          orElse: () => [],
        );
        if (firstPaths.isNotEmpty) {
          _paths = List<String>.from(firstPaths);
        }
      }
    }

    // only try to play if we have at least one path
    _index = _safeIndexClamp(0);
    debugPrint('Initial video paths: $_index / ${_paths.length}');
    if (_paths.isNotEmpty) {
      _initAndPlay(_index);
    } else {
      // nothing to play — set a friendly error so UI shows message instead of spinning/crashing
      setState(() {
        _errorMsg = 'No videos available';
        _ready = false;
      });
    }

    // orientation + immersive
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // listen for campaign changes
    widget.campaignNotifier?.addListener(_onCampaignChanged);
  }

  void _onCampaignChanged() {
    final val = widget.campaignNotifier?.value;
    if (val != null && val.isNotEmpty) {
      // clear dropdown selection (we show Default when campaign originates externally)
      setState(() => _selectedCampaignName = null);
      _switchToPlaylist(val, startIndex: 0);
    } else {
      // external cleared campaign -> resume default
      _resumeDefault();
    }
  }

  Future<void> _switchToPlaylist(
    List<String> newPaths, {
    int startIndex = 0,
    String? campaignName,
  }) async {
    if (newPaths.isEmpty) return;
    _isSeeking = true;
    _errorMsg = null;
    setState(() {
      _ready = false;
      _selectedCampaignName = campaignName;
    });

    try {
      await _controller?.pause();
      await _controller?.dispose();
    } catch (_) {}

    _paths = List<String>.from(newPaths);
    _usingDefault = false;
    _index = _safeIndexClamp(startIndex);

    _initAndPlay(_index);
  }

  void _resumeDefault() {
    _paths = List<String>.from(widget.defaultPaths);
    _selectedCampaignName = null;
    _usingDefault = true;
    _initAndPlay(0);
  }

  Future<void> _initAndPlay(int index) async {
    if (_paths.isEmpty) {
      setState(() {
        _errorMsg = 'No videos available to play';
        _ready = false;
      });
      return;
    }
    if (index < 0 || index >= _paths.length) return;
    debugPrint('Initializing video at index $index');
    _isSeeking = true;
    _errorMsg = null;
    setState(() {
      _ready = false;
    });

    try {
      await _controller?.pause();
      await _controller?.dispose();
    } catch (_) {}

    final path = _paths[index];
    final file = File(path);
    if (!await file.exists()) {
      _errorMsg = 'File not found:\n$path';
      // try next available
      final next = await _nextIndex(index);
      if (next != null && next != index) {
        _initAndPlay(next);
        return;
      }

      // No next in this playlist
      if (!_isDefault) {
        // campaign finished or failed -> clear campaign and resume default
        widget.campaignNotifier?.value = null;
        _resumeDefault();
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
      if (_isDefault) {
        ctrl.setLooping(true);
        debugPrint('Playing video file: $path');
      } else {
        ctrl.setLooping(false);
        debugPrint('Playing not default video file: $path');
      }

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
      // if campaign ended due to error, resume default
      if (!_isDefault) {
        widget.campaignNotifier?.value = null;
        _resumeDefault();
        return;
      }
      setState(() {});
    } finally {
      _isSeeking = false;
    }
  }

  Future<void> _playerListener() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    final pos = c.value.position;
    final dur = c.value.duration;
    if (dur != null && pos >= dur - const Duration(milliseconds: 250)) {
      // reached end
      if (!_isSeeking) {
        final nextIdx = _index + 1;
        if (nextIdx < _paths.length) {
          _initAndPlay(nextIdx);
        } else {
          // playlist finished
          if (!_isDefault) {
            widget.campaignNotifier?.value = null;
            _resumeDefault();
          } else if (widget.loopDefault) {
            // loop default playlist *without reinitializing*
            try {
              // simply seek to start and play again — avoids creating a new controller
              await c.seekTo(Duration.zero);
              if (!c.value.isPlaying) await c.play();
            } catch (e) {
              // fallback: if seeking fails for some reason, fall back to your existing behavior
              _initAndPlay(0);
            } 
          }
        }
      }
    }
  }

  Future<int?> _nextIndex(int from) async {
    final next = from + 1;
    if (next < _paths.length) return next;
    return null;
  }

  Future<int?> _prevIndex(int from) async {
    final prev = from - 1;
    if (prev >= 0) return prev;
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
    widget.campaignNotifier?.removeListener(_onCampaignChanged);
    _controller?.removeListener(_playerListener);
    _controller?.pause();
    _controller?.dispose();

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
            Center(
              child:
                  _errorMsg != null
                      ? _buildError()
                      : _ready && c != null
                      ? AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: VideoPlayer(c),
                      )
                      : const SizedBox(),
            ),

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
                      (_paths.isNotEmpty &&
                              _index >= 0 &&
                              _index < _paths.length)
                          ? _paths[_index].split('/').last
                          : 'No video',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // DROPDOWN
                  const SizedBox(width: 12),
                  _inputUser(),

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

  bool _ageInRange(int age, String range) {
    range = range.trim();
    if (range.contains('-')) {
      final parts =
          range.split('-').map((s) => int.tryParse(s.trim())).toList();
      if (parts.length == 2 && parts[0] != null && parts[1] != null) {
        return age >= parts[0]! && age <= parts[1]!;
      }
    } else if (range.endsWith('+')) {
      debugPrint('Checking if age $age >= $range');
      final start = int.tryParse(range.replaceAll('+', '').trim());
      if (start != null) return age >= start;
    } else {
      // single number?
      final v = int.tryParse(range);
      if (v != null) return age == v;
    }
    return false;
  }

  bool checkCapability(Campaign c, int age, String? gender) {
    // normalize
    final userGender = (gender ?? '').toLowerCase();
    // Age match: true if any age bucket matches
    var ageMatch = false;
    for (var ageRange in c.age ?? []) {
      if (_ageInRange(age, ageRange)) {
        ageMatch = true;
        debugPrint(
          '✅ Age $age matches range $ageRange in campaign ${c.campaignName}',
        );
        break;
      } else {
        debugPrint(
          '❓ Age $age does not match range $ageRange in campaign ${c.campaignName}',
        );
      }
    }

    // Gender match: if campaign allows 'all' or contains the user's gender
    var genderMatch = false;
    final campaignGenders =
        (c.gender ?? []).map((g) => g.toString().toLowerCase()).toList();
    if (campaignGenders.isEmpty || campaignGenders.contains('all')) {
      genderMatch = true;
      debugPrint('✅ Campaign ${c.campaignName} allows all genders');
    } else if (userGender.isNotEmpty) {
      if (campaignGenders.contains(userGender)) {
        genderMatch = true;
        debugPrint('✅ Gender $userGender matches campaign ${c.campaignName}');
      } else {
        debugPrint(
          '❓ Gender $userGender NOT matched in campaign ${c.campaignName}',
        );
      }
    } else {
      // no user gender provided -> consider it not matched
      debugPrint(
        '❓ No user gender provided for matching against ${c.campaignName}',
      );
    }

    return ageMatch && genderMatch;
  }

  String? _selectedGender;
  TextEditingController _ageController = TextEditingController();
  List<Campaign> campaignMatched = [];
  List<int>? videoIds;
  Widget _inputUser() {
    return ElevatedButton(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) {
            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Input User Data'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text('Gender: '),
                          SizedBox(width: 16),
                          DropdownButton<String>(
                            value: _selectedGender,
                            hint: const Text('Select Gender'),
                            items:
                                <String>['Male', 'Female'].map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value),
                                  );
                                }).toList(),
                            onChanged: (newValue) {
                              setState(() {
                                _selectedGender = newValue;
                              });
                            },
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text('Age: '),
                          SizedBox(width: 16),
                          SizedBox(
                            width: 50,
                            child: TextField(
                              controller: _ageController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: 'Age',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 8,
                                ),
                              ),
                              maxLines: 1,
                              maxLength: 3,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          final ageText = _ageController.text.trim();
                          final parsedAge = int.tryParse(ageText);
                          final genderRaw = _selectedGender ?? '';
                          final genderNormalized = genderRaw.toLowerCase();

                          if (parsedAge == null || genderNormalized.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please enter a valid age and select a gender',
                                ),
                              ),
                            );
                            return;
                          }

                          // ensure campaigns are loaded
                          if (campaigns.isEmpty) {
                            // try refetching once
                            if (campaigns.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'No campaign metadata available',
                                  ),
                                ),
                              );
                              Navigator.of(context).pop();
                              return;
                            }
                          }

                          // clear previous matches
                          campaignMatched = [];

                          // collect matches
                          for (final c in campaigns) {
                            debugPrint(
                              'Checking campaign: with age ranges: ${c.age} and genders: ${c.gender}',
                            );
                            final isMatch = checkCapability(
                              c,
                              parsedAge,
                              genderNormalized,
                            );
                            debugPrint(
                              'Capability result for campaign ${c.campaignName}: $isMatch',
                            );
                            if (isMatch) {
                              campaignMatched.add(c);
                            }
                          }
                          videoIds =
                              campaignMatched
                                  .map((e) => e.videoIds ?? [])
                                  .expand((i) => i)
                                  .toSet()
                                  .toList();
                          debugPrint('Matched video IDs: $videoIds');

                          Navigator.of(context).pop(); // close dialog

                          debugPrint(
                            'Matched campaigns: ${campaignMatched.map((e) => e.campaignName).toList()}',
                          );

                          var needToPlay =
                              _videos
                                  .where(
                                    (v) => videoIds?.contains(v.id) ?? false,
                                  )
                                  .toList();
                          debugPrint(
                            'Videos to play from matched campaigns: ${needToPlay.map((e) => e.videoName).toList()}',
                          );

                          if (campaignMatched.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No matching campaign — resuming default',
                                ),
                              ),
                            );
                            _resumeDefault();
                            return;
                          }
                          final now = DateTime.now();
                          final folderName =
                              '${now.year}-${two(now.month)}-${two(now.day)}';
                          final base =
                              '/storage/emulated/0/Download/Advatar/$folderName';
                          // Build combined playlist from all matched campaigns
                          final List<String> combinedPaths = [];
                          for (final x in needToPlay) {
                            final filePath = p.join(base, x.videoName + '.mp4');
                            final file = File(filePath);
                            if (await file.exists()) {
                              debugPrint(
                                'Adding file for video ${x.videoName} at $filePath',
                              );
                              combinedPaths.add(filePath);
                            } else {
                              debugPrint(
                                'File for video ${x.videoName} not found at $filePath',
                              );
                            }
                          }

                          // Remove duplicates while preserving order
                          final seen = <String>{};
                          final List<String> uniquePaths = [];
                          for (final p in combinedPaths) {
                            if (!seen.contains(p)) {
                              seen.add(p);
                              uniquePaths.add(p);
                            }
                          }

                          if (uniquePaths.isEmpty) {
                            // nothing to play from matched campaigns
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Matched campaigns found but no local files available — resuming default',
                                ),
                              ),
                            );
                            _resumeDefault();
                            return;
                          }

                          // Optional: show a small confirmation/toast listing which campaigns will be played
                          final names = campaignMatched
                              .map((c) => c.campaignName)
                              .join(', ');
                          debugPrint(
                            'Playing matched campaigns in order: $names',
                          );

                          // Switch to the combined playlist. We set campaignName to indicate multi.
                          _switchToPlaylist(
                            uniquePaths,
                            campaignName: 'Multiple: ${campaignMatched.length}',
                          );
                        },

                        child: const Text('Submit'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
      child: Text('Input'),
    );
  }
}
