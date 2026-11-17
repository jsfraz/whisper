import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/text_envelope.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  test('a reply survives the round trip', () {
    final sentAt = DateTime(2026, 3, 4, 5, 6, 7);
    final envelope = buildTextEnvelope(
        'souhlasím',
        ReplyRef(
          senderId: 'peer',
          sentAt: sentAt,
          preview: ReplyRef.previewOf('původní zpráva'),
        ));

    final parsed = tryParseTextEnvelope(envelope);
    expect(parsed, isNotNull);
    expect(parsed!.body, 'souhlasím');
    expect(parsed.reply!.senderId, 'peer');
    expect(parsed.reply!.sentAt, sentAt);
    expect(parsed.reply!.preview, 'původní zpráva');
  });

  test('the envelope is not a media envelope', () {
    final envelope = buildTextEnvelope(
        'x', ReplyRef(senderId: 'a', sentAt: DateTime(2026), preview: 'y'));
    final decoded = jsonDecode(utf8.decode(envelope)) as Map;
    expect(decoded['kind'], 'text');
    expect(decoded['whisperMsg'], textEnvelopeVersion);
  });

  test('plain text is not an envelope', () {
    expect(tryParseTextEnvelope(bytes('ahoj')), isNull);
  });

  test('a media envelope is not a text envelope', () {
    final media = bytes('{"whisperMsg":1,"kind":"media","media":{}}');
    expect(tryParseTextEnvelope(media), isNull);
  });

  test('a broken body is not an envelope', () {
    final broken = bytes('{"whisperMsg":3,"kind":"text","body":5}');
    expect(tryParseTextEnvelope(broken), isNull);
  });

  test('a broken quote is ignored, the body still reads', () {
    final broken =
        bytes('{"whisperMsg":3,"kind":"text","body":"a","replyTo":{"x":1}}');
    final parsed = tryParseTextEnvelope(broken);
    expect(parsed!.body, 'a');
    expect(parsed.reply, isNull);
  });

  test('the preview is capped', () {
    final long = 'x' * (ReplyRef.maxPreviewLength + 50);
    final preview = ReplyRef.previewOf(long);
    expect(preview.length, ReplyRef.maxPreviewLength + 1);
    expect(preview.endsWith('…'), isTrue);
  });
}
