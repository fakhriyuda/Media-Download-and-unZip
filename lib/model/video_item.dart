class VideoItem {
  final int id;
  final String videoName;
  final List<String> age;
  final List<String> gender;
  int? downloaded; // nullable, default to false

  VideoItem({
    required this.id,
    required this.videoName,
    required this.age,
    required this.gender,
    this.downloaded = 0,
  });

  factory VideoItem.fromJson(Map<String, dynamic> j) {
    return VideoItem(
      id: j['id'] is int ? j['id'] : int.parse(j['id'].toString()),
      videoName: j['video_name'] ?? '',
      age: List<String>.from(j['age'] ?? []),
      gender: List<String>.from(j['gender'] ?? []),
      downloaded: j['downloaded'] is int ? j['downloaded'] : (j['downloaded'] == true ? 1 : 0),
    );
  }
}

class DownloadedFile {
  final int? id;
  final String filename;
  final String path;
  final int size; // bytes
  final String savedAtIso; // ISO 8601 timestamp
  final int extracted; // 0 = false, 1 = true

  DownloadedFile({
    this.id,
    required this.filename,
    required this.path,
    required this.size,
    required this.savedAtIso,
    this.extracted = 0,
  });

  factory DownloadedFile.fromMap(Map<String, dynamic> m) => DownloadedFile(
    id: m['id'] as int?,
    filename: m['filename'] as String,
    path: m['path'] as String,
    size: m['size'] as int,
    savedAtIso: m['saved_at'] as String,
    extracted: m['extracted'] as int? ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'filename': filename,
    'path': path,
    'size': size,
    'saved_at': savedAtIso,
    'extracted': extracted,
  };
}
