// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invite_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InviteData _$InviteDataFromJson(Map<String, dynamic> json) => InviteData(
      json['url'] as String,
      json['code'] as String,
      DateTime.parse(json['validUntil'] as String),
    );

// ignore: unused_element
Map<String, dynamic> _$InviteDataToJson(InviteData instance) =>
    <String, dynamic>{
      'url': instance.url,
      'code': instance.code,
      'validUntil': instance.validUntil.toIso8601String(),
    };
