import 'package:flutter_test/flutter_test.dart';
import 'package:shept/utils/playback_speed.dart';

void main() {
  test('cycles through 1x, 1.5x, 2x and back', () {
    expect(nextSpeed(1.0), 1.5);
    expect(nextSpeed(1.5), 2.0);
    expect(nextSpeed(2.0), 1.0);
  });

  test('unknown speed falls back to 1x', () {
    expect(nextSpeed(0.5), 1.0);
  });

  test('labels drop the decimal for whole speeds', () {
    expect(speedLabel(1.0), '1x');
    expect(speedLabel(1.5), '1.5x');
    expect(speedLabel(2.0), '2x');
  });
}
