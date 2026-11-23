import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/mp4_rotation.dart';

void main() {
  test('a clip stored landscape with a rotation reports 90', () async {
    // 160x120 coded frame plus a 90 degree display matrix, the shape a phone
    // records when it is held upright.
    final rotation =
        await Mp4Rotation.ofFile(File('test/fixtures/portrait.mp4'));

    expect(rotation, 90);
  });

  test('a file that is not an mp4 reports no rotation', () async {
    final file = File('${Directory.systemTemp.path}/whisper_not_a_video.mp4');
    await file.writeAsBytes(List<int>.filled(64, 0));
    addTearDown(() => file.deleteSync());

    expect(await Mp4Rotation.ofFile(file), 0);
  });
}
