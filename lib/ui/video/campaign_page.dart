import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yudvatar/model/video_item.dart';
import 'package:yudvatar/services/videos_db.dart';
import 'package:yudvatar/ui/video/playlist_page.dart';
import 'package:yudvatar/ui/video/video_player_page.dart';

class CampaignPage extends StatefulWidget {
  const CampaignPage({super.key});

  @override
  State<CampaignPage> createState() => _CampaignPageState();
}

class _CampaignPageState extends State<CampaignPage> {
  // Example campaign data (from our earlier JSON)
  final List<Map<String, dynamic>> _campaigns = [
    {
      "campaign_id": 1,
      "campaign_name": "Gen Z Starter",
      "description": "Konten untuk anak dan remaja",
      "age": ["0-17"],
      "gender": ["male", "female"],
      "video_ids": [1, 4],
    },
    {
      "campaign_id": 2,
      "campaign_name": "Young Adult Female",
      "description": "Konten fokus perempuan dewasa muda",
      "age": ["18-34"],
      "gender": ["female"],
      "video_ids": [2, 5],
    },
    {
      "campaign_id": 3,
      "campaign_name": "Adult Reach",
      "description": "Konten untuk dewasa (lebih luas, inklusif gender)",
      "age": ["18-34", "35+"],
      "gender": ["male", "female"],
      "video_ids": [3, 5],
    },
  ];

  // Example mapping videoId -> videoName (so the UI looks nicer)
  final Map<int, String> _videoMap = {
    1: 'sample_1',
    2: 'sample_2',
    3: 'sample_3',
    4: 'sample_4',
    5: 'sample_5',
  };

  // Track which panels are expanded (optional)
  final Set<int> _expanded = {};
  final _videoDb = VideoDb();
  List<VideoItem> videos = [];

  @override
  void initState() {
    super.initState();
    _loadVideoNames();
  }

  Future<void> _loadVideoNames() async {
    videos = await _videoDb.getAllVideos();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('List Campaign')),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _campaigns.length,
        itemBuilder: (context, index) {
          final campaign = _campaigns[index];
          final id = campaign['campaign_id'] as int;
          final name = campaign['campaign_name'] as String;
          final desc = campaign['description'] as String? ?? '';
          final ages = List<String>.from(campaign['age'] as List);
          final genders = List<String>.from(campaign['gender'] as List);
          final videoIds = List<int>.from(campaign['video_ids'] as List);

          final isExpanded = _expanded.contains(id);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ExpansionTile(
              key: ValueKey(id),
              shape: Border(),
              initiallyExpanded: isExpanded,
              expandedAlignment: Alignment.centerLeft,
              onExpansionChanged: (open) {
                setState(() {
                  if (open) {
                    _expanded.add(id);
                  } else {
                    _expanded.remove(id);
                  }
                });
              },
              title: Row(
                children: [
                  CircleAvatar(child: Text(id.toString()), radius: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          desc,
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              childrenPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              children: [
                // Age chips
                Align(
                  child: Text(
                    'Age',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  alignment: Alignment.centerLeft,
                ),
                const SizedBox(height: 4),
                Row(
                  spacing: 8,
                  children: [
                    ...ages.map(
                      (a) => Chip(
                        label: Text(
                          a,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        backgroundColor: Colors.blue.shade50,
                      ),
                    ),
                    Spacer(),
                    ElevatedButton(
                      onPressed: () {
                        // playlist:
                        final now = DateTime.now();
                        final folderName =
                            '${now.year}-${two(now.month)}-${two(now.day)}';
                        List<String> videoPaths = [];
                        videoPaths =
                            videos.where((v) => videoIds.contains(v.id)).map((
                              v,
                            ) {
                              return '/storage/emulated/0/Download/Advatar/$folderName/${v.videoName}.mp4';
                            }).toList();
                        debugPrint('Play video paths: $videoPaths');

                        // Navigator.of(context).push(
                        //   MaterialPageRoute(
                        //     builder:
                        //         (_) => FullscreenVideoPlayer(
                        //           filePaths:
                        //               videoIds
                        //                   .map(
                        //                     (id) =>
                        //                         '/storage/emulated/0/Download/Advatar/sample_$id.mp4',
                        //                   )
                        //                   .toList(),
                        //         ),
                        //   ),
                        // );
                      },
                      child: Text("Play All"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Gender',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 4),

                // Gender chips
                Row(
                  spacing: 8,
                  children: [
                    ...genders.map(
                      (g) => Chip(
                        label: Text(g.toString().toUpperCase()),
                        backgroundColor: Colors.green.shade50,
                        labelStyle: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                const Divider(),

                // Videos list header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Videos (${videoIds.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),

                // Video items
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: videoIds.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final vid = videoIds[i];
                    final vname = _videoMap[vid] ?? 'video_$vid';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 18,
                        child: Text(vid.toString()),
                      ),
                      title: Text(vname),
                      subtitle: Text('id: $vid'),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
