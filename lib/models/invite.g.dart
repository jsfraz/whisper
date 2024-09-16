// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Invite _$InviteFromJson(Map<String, dynamic> json) => Invite(
      json['url'] as String,
      json['code'] as String,
      DateTime.parse(json['validUntil'] as String),
    );

Map<String, dynamic> _$InviteToJson(Invite instance) => <String, dynamic>{
      'url': instance.url,
      'code': instance.code,
      'validUntil': instance.validUntil.toIso8601String(),
    };
