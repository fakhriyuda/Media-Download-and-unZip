import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:yudvatar/model/campaign.dart';
import 'package:yudvatar/model/video_item.dart';
import 'package:yudvatar/services/campaigns_db.dart';
import 'package:yudvatar/services/videos_db.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:yudvatar/ui/video/campaign_page.dart';
import 'package:yudvatar/ui/video/video_player_page.dart';

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({Key? key}) : super(key: key);

  @override
  State<PlaylistPage> createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  final Dio _dio = Dio();
  final String _jsonUrl =
      'https://vercel-server-universal-link.vercel.app/api/videos/raw.json';
  List<VideoItem> _videos = [];
  List<Campaign> campaigns = [];
  bool _loading = false;
  String? _error;

  final _videoDb = VideoDb();
  final _campaignDb = CampaignDb();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final local = await _videoDb.getAllVideos();
      final localCampaigns = await _campaignDb.getAllCampaigns();
      debugPrint('Loaded ${local.length} local videos from DB');
      debugPrint('Loaded ${localCampaigns.length} local campaigns from DB');
      setState(() {
        _videos = local;
        campaigns = localCampaigns;
        _loading = false;
      });
    } catch (e) {
      // if DB read fails, still allow fetching from server
      setState(() {
        _loading = false;
        _error = 'Failed to load local videos: $e';
      });
    }
  }

  Future<void> fetchVideos() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _dio.get(
        _jsonUrl,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data;
        List list;
        if (data is String) {
          list = json.decode(data) as List;
        } else if (data is List) {
          list = data;
        } else {
          throw Exception('Unexpected JSON format');
        }

        final fetched =
            list
                .map((e) => VideoItem.fromJson(e as Map<String, dynamic>))
                .toList();

        // Save/upsert into local DB and reload from DB so local downloaded flags persist
        await _videoDb.upsertVideos(fetched);
        final local = await _videoDb.getAllVideos();

        setState(() {
          _videos = local;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Server returned ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to fetch: $e';
        _loading = false;
      });
    }
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: fetchVideos, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_videos.isEmpty) {
      return const Center(child: Text('No videos found'));
    }

    return RefreshIndicator(
      onRefresh: fetchVideos,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        itemCount: _videos.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final v = _videos[index];
          // show downloaded badge if available
          final downloaded = (v.downloaded ?? 0) == 1;
          return ListTile(
            leading: CircleAvatar(child: Text(v.id.toString())),
            title: Text(v.videoName),
            subtitle: Text('${v.age.join(', ')} • ${v.gender.join(', ')}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (downloaded)
                  const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded),
                  onPressed: () {
                    final now = DateTime.now();
                    final folderName =
                        '${now.year}-${two(now.month)}-${two(now.day)}';
                    var pathFile = File(
                      '/storage/emulated/0/Download/Advatar/$folderName/${v.videoName}.mp4',
                    );
                    debugPrint('Playing video from $pathFile');

                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) => FullscreenVideoPlayer(
                              defaultPaths: [pathFile.path],
                              campaignNotifier: campaignNotifier,
                            ),
                      ),
                    );
                  },
                ),
              ],
            ),
            onTap: () {},
          );
        },
      ),
    );
  }

  Future<void> getAllCampaign() async {
    var _campaignUrl =
        'https://vercel-server-universal-link.vercel.app/api/videos/campaign.json';
    try {
      final response = await _dio.get(
        _campaignUrl,
        options: Options(
          responseType: ResponseType.json,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      debugPrint('Campaign data: ${response.data}');

      final rawList = parseResponseData(response.data);

      final loaded = rawList.map((item) => Campaign.fromJson(item)).toList();

      setState(() {
        campaigns = loaded;
      });

      try {
        await _campaignDb.upsertCampaigns(rawList);
        debugPrint('Saved ${rawList.length} campaigns to local DB.');
      } catch (dbErr, st) {
        debugPrint('Failed to save campaigns locally: $dbErr\n$st');
      }
    } catch (e, st) {
      debugPrint('Failed to load campaigns from network: $e\n$st');
      // FALLBACK: Load from local DB
      try {
        final rawLocal = await _campaignDb.getAllCampaigns();
        debugPrint('Loaded ${rawLocal.length} campaigns from local DB.');
        setState(() {
          campaigns = rawLocal;
        });
      } catch (localErr, localSt) {
        debugPrint(
          'Failed to load campaigns from local DB: $localErr\n$localSt',
        );
        // keep campaigns empty — UI will handle it
      }
    }
  }

  List<Map<String, dynamic>> parseResponseData(dynamic data) {
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is Map && data['data'] is List) {
      return (data['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  void onDownloadAllPressed() {
    final url =
        'https://vercel-server-universal-link.vercel.app/videos/Archive.zip';
    final progressNotifier = ValueNotifier<double>(0.0);
    final cancelToken = CancelToken();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (_, value, __) {
            final percentText =
                value >= 0 ? '${(value * 100).toStringAsFixed(0)}%' : '...';
            final indicator =
                value >= 0
                    ? LinearProgressIndicator(value: value)
                    : const LinearProgressIndicator();

            return AlertDialog(
              title: const Text('Downloading archive'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  indicator,
                  const SizedBox(height: 12),
                  Text('Downloading: $percentText'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    cancelToken.cancel('User cancelled');
                    Navigator.of(ctx, rootNavigator: true).pop();
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );

    downloadSingleWithProgress(
          context: context,
          url: url,
          progressNotifier: progressNotifier,
          cancelToken: cancelToken,
          extractZipAfter: true,
        )
        .then((savePath) async {
          debugPrint('Downloaded to $savePath');
          // close dialog if open
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (_) {}

          // Mark all videos in DB as downloaded
          try {
            await _videoDb.markAllDownloaded(downloaded: 1);
            final local = await _videoDb.getAllVideos();
            setState(() => _videos = local);
          } catch (e) {
            debugPrint('Failed to mark downloaded: $e');
          }

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Downloaded to $savePath')));
        })
        .catchError((err) {
          // close dialog if open
          try {
            Navigator.of(context, rootNavigator: true).pop();
          } catch (_) {}

          final msg = err?.toString() ?? 'Unknown error';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Download failedz: $msg')));
        });
  }

  // your downloadSingleWithProgress stays the same (writing to Download/<date>/...), no DB code here
  Future<String> downloadSingleWithProgress({
    required BuildContext context,
    required String url,
    required ValueNotifier<double> progressNotifier,
    required CancelToken cancelToken,
    required bool extractZipAfter,
  }) async {
    final allowed = await ensureWriteToDownloadsPermission(context);
    if (!allowed) {
      throw Exception('Storage permission not granted');
    }
    final base = '/storage/emulated/0/Download/';
    final now = DateTime.now();

    final dirPath = p.join(base, 'Advatar');
    final tempFile = '${now.year}-${two(now.month)}-${two(now.day)}';
    final filename = '$tempFile.zip';
    final savePath = p.join(dirPath, filename);

    debugPrint('Downloading $url to $savePath');

    // ensure dir exists
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    debugPrint('Requesting storage permission...');

    try {
      var test = await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            progressNotifier.value = received / total;
          } else {
            progressNotifier.value = -1;
          }
        },
        options: Options(
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      debugPrint('Download response: $test');

      final f = File(savePath);
      if (!await f.exists()) throw Exception('File not created');
      final size = await f.length();
      if (size < 100) {
        final content = await f.readAsString();
        throw Exception('Downloaded file too small: $content');
      }

      if (extractZipAfter) {
        // show extracting dialog and extract
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (_) => const AlertDialog(
                title: Text('Extracting...'),
                content: SizedBox(
                  height: 60,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
        );

        final destDir = Directory(
          p.join(dirPath, p.basenameWithoutExtension(filename)),
        );
        if (!await destDir.exists()) await destDir.create(recursive: true);
        try {
          await ZipFile.extractToDirectory(zipFile: f, destinationDir: destDir);
        } finally {
          Navigator.of(context, rootNavigator: true).pop();
          await fetchVideos(); // refresh list from DB if extraction adds files/changes
          await getAllCampaign(); // refresh campaigns too
        }
      }

      return savePath;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw Exception('Download cancelled');
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  ValueNotifier<List<String>?> campaignNotifier = ValueNotifier(null);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CampaignPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _videoDb.getAllVideos,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download),
            tooltip: 'Download all',
            onPressed: onDownloadAllPressed,
          ),
        ],
      ),
      body: _buildList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final now = DateTime.now();
          final folderName = '${now.year}-${two(now.month)}-${two(now.day)}';
          var pathFile = File(
            '/storage/emulated/0/Download/Advatar/$folderName/default.mp4',
          );
          debugPrint('Playing video from $pathFile');
          // final campaignMap = {
          //   'Gen Z Starter': [
          //     '/sdcard/Download/Advatar/2025-10-16/sample_1.mp4',
          //     '/sdcard/Download/Advatar/2025-10-16/sample_4.mp4',
          //   ],
          //   'Young Adult Female': [
          //     '/sdcard/Download/Advatar/2025-10-16/sample_2.mp4',
          //     '/sdcard/Download/Advatar/2025-10-16/sample_5.mp4',
          //   ],
          // };
          Navigator.of(context).push(
            MaterialPageRoute(
              builder:
                  (_) => FullscreenVideoPlayer(
                    defaultPaths: [pathFile.path],
                    campaignNotifier: campaignNotifier,
                    videoItems: _videos,
                    campaigns: campaigns,
                  ),
            ),
          );
        },
        tooltip: 'Fetch from server',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<int> _androidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    final info = DeviceInfoPlugin();
    final android = await info.androidInfo;
    return android.version.sdkInt ?? 0;
  }

  /// Ensure permission to write into Downloads path (/storage/emulated/0/Download)
  /// Returns true when allowed to write to that path.
  Future<bool> ensureWriteToDownloadsPermission(BuildContext context) async {
    if (!Platform.isAndroid) return true; // not needed on iOS

    final sdk = await _androidSdkInt();

    // Android 9 and below (<=28): request WRITE_EXTERNAL_STORAGE
    if (sdk <= 28) {
      final status = await Permission.storage.status;
      if (status.isGranted) return true;
      final req = await Permission.storage.request();
      if (req.isGranted) return true;

      if (req.isPermanentlyDenied) {
        // show dialog to guide user to settings
        final open = await _showOpenSettingsDialog(
          context,
          'Storage permission required to save to Downloads. Open app settings to grant permission?',
        );
        if (open) openAppSettings();
      }
      return false;
    }

    // Android 10 (API 29): scoped storage introduced; direct writes may be limited but writing to public Download path is not allowed without proper APIs.
    if (sdk == 29) {
      // Try requesting legacy storage flag is compile time; runtime we still request storage permission as fallback
      final status = await Permission.storage.status;
      if (status.isGranted) return true;
      final req = await Permission.storage.request();
      if (req.isGranted) return true;
      if (req.isPermanentlyDenied) {
        final open = await _showOpenSettingsDialog(
          context,
          'Storage permission required. Open app settings to grant permission?',
        );
        if (open) openAppSettings();
      }
      return false;
    }

    // Android 11+ (API >= 30): use MANAGE_EXTERNAL_STORAGE if you insist on direct file path,
    // but Google Play disallows it except special use-cases. This code will request it and guide user to settings.
    if (sdk >= 30) {
      // permission_handler exposes manageExternalStorage
      final status = await Permission.manageExternalStorage.status;
      if (status.isGranted) return true;

      final req = await Permission.manageExternalStorage.request();
      if (req.isGranted) return true;

      // If denied, ask user to open settings because this permission requires manual action
      if (req.isPermanentlyDenied || !req.isGranted) {
        final open = await _showOpenSettingsDialog(
          context,
          'Allow "All files access" for this app to save into the Downloads folder? Open settings now?',
        );
        if (open) openAppSettings();
      }
      return false;
    }

    return false;
  }

  Future<bool> _showOpenSettingsDialog(
    BuildContext context,
    String text,
  ) async {
    final res = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Permission required'),
            content: Text(text),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Open settings'),
              ),
            ],
          ),
    );
    return res ?? false;
  }
}

String two(int n) => n.toString().padLeft(2, '0');
