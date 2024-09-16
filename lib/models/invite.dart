import 'package:json_annotation/json_annotation.dart';

part 'invite.g.dart';

// https://docs.flutter.dev/data-and-backend/serialization/json#serializing-json-using-code-generation-libraries

@JsonSerializable()
class Invite {
  Invite(this.url, this.code, this.validUntil);

  String url;
  String code;
  DateTime validUntil;

  factory Invite.fromJson(Map<String, dynamic> json) => _$InviteFromJson(json);
}