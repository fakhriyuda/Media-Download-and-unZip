import 'dart:convert';

class Campaign {
  int? campaignId;
  String? campaignName;
  String? description;
  List<String>? age;
  List<String>? gender;
  List<int>? videoIds;

  Campaign({
    this.campaignId,
    this.campaignName,
    this.description,
    this.age,
    this.gender,
    this.videoIds,
  });

  factory Campaign.fromRawJson(String str) =>
      Campaign.fromJson(json.decode(str));

  String toRawJson() => json.encode(toJson());

  factory Campaign.fromJson(Map<String, dynamic> json) => Campaign(
    campaignId: json["campaign_id"],
    campaignName: json["campaign_name"],
    description: json["description"],
    age:
        json["age"] == null
            ? []
            : List<String>.from(json["age"]!.map((x) => x)),
    gender:
        json["gender"] == null
            ? []
            : List<String>.from(json["gender"]!.map((x) => x)),
    videoIds:
        json["video_ids"] == null
            ? []
            : List<int>.from(json["video_ids"]!.map((x) => x)),
  );

  Map<String, dynamic> toJson() => {
    "campaign_id": campaignId,
    "campaign_name": campaignName,
    "description": description,
    "age": age == null ? [] : List<dynamic>.from(age!.map((x) => x)),
    "gender": gender == null ? [] : List<dynamic>.from(gender!.map((x) => x)),
    "video_ids":
        videoIds == null ? [] : List<dynamic>.from(videoIds!.map((x) => x)),
  };
}
