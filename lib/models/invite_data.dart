import 'package:json_annotation/json_annotation.dart';

part 'invite_data.g.dart';

// https://docs.flutter.dev/data-and-backend/serialization/json#serializing-json-using-code-generation-libraries

@JsonSerializable()
class InviteData {
  InviteData(this.url, this.code, this.validUntil);

  String url;
  String code;
  DateTime validUntil;

  factory InviteData.fromJson(Map<String, dynamic> json) => _$InviteDataFromJson(json);
}