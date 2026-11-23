import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/models/private_message.dart';
import 'package:whisper_websocket_client_dart/models/media_reference.dart';
import 'package:whisper_websocket_client_dart/models/media_type.dart';

void main() {
  PrivateMessage video({String? referenceJson}) => PrivateMessage(
        '1',
        '',
        DateTime(2026, 11, 23),
        DateTime(2026, 11, 23),
        true,
        mediaTypeStr: 'video',
        mediaRefJson: referenceJson,
      );

  String referenceJson({required bool note}) => jsonEncode(MediaReference(
        'id',
        Uint8List(32),
        MediaType.video,
        1024,
        videoNote: note,
      ).toJson());

  test('a round note is recognised from its finished reference', () {
    expect(video(referenceJson: referenceJson(note: true)).isVideoNote, isTrue);
  });

  test('a round note still sending is recognised from its marker', () {
    expect(video(referenceJson: '{"videoNote":true}').isVideoNote, isTrue);
  });

  test('a plain video is not a round note', () {
    expect(
        video(referenceJson: referenceJson(note: false)).isVideoNote, isFalse);
    expect(video().isVideoNote, isFalse);
  });
}
