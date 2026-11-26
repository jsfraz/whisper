import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shept/utils/round_note_playback.dart';

void main() {
  group('the floating copy of a round note', () {
    test('appears for a live note that is mostly out of sight', () {
      expect(shouldPin(active: true, visibleFraction: 0.4), isTrue);
      expect(shouldPin(active: true, visibleFraction: 0), isTrue);
    });

    test('stays away while the circle is on screen', () {
      expect(shouldPin(active: true, visibleFraction: 0.5), isFalse);
      expect(shouldPin(active: true, visibleFraction: 1), isFalse);
    });

    test('is gone when the note finished or was dismissed', () {
      expect(shouldPin(active: false, visibleFraction: 0), isFalse);
      expect(shouldPin(active: false, visibleFraction: 0.9), isFalse);
    });
  });

  group('a rubber-band bounce', () {
    const viewport = Rect.fromLTWH(0, 0, 400, 800);

    test('measures as if the list had settled', () {
      // Dragging down at the top of a reversed chat pulls the note 120 dp
      // lower than it will sit once released.
      const pulled = Rect.fromLTRB(0, 700, 230, 930);
      final settled = settledNoteRect(pulled, overscroll: -120, reversed: true);
      expect(settled, const Rect.fromLTRB(0, 580, 230, 810));
      expect(visibleFraction(pulled, viewport), lessThan(0.5));
      expect(visibleFraction(settled, viewport), greaterThan(0.9));
    });

    test('is ignored when the list is inside its range', () {
      const note = Rect.fromLTRB(0, 300, 230, 530);
      expect(settledNoteRect(note, overscroll: 0, reversed: true), note);
    });

    test('the shift follows the list direction', () {
      const note = Rect.fromLTRB(0, 600, 230, 830);
      expect(
        settledNoteRect(note, overscroll: 120, reversed: true),
        const Rect.fromLTRB(0, 720, 230, 950),
      );
      expect(
        settledNoteRect(note, overscroll: 120, reversed: false),
        const Rect.fromLTRB(0, 480, 230, 710),
      );
    });
  });

  group('the share of the note on screen', () {
    const note = Rect.fromLTWH(0, 0, 200, 200);

    test('is 1 when the whole circle is inside the viewport', () {
      expect(visibleFraction(note, const Rect.fromLTWH(0, 0, 400, 800)), 1);
    });

    test('is the covered part when the circle is half way out', () {
      expect(visibleFraction(note, const Rect.fromLTWH(0, 100, 400, 800)), 0.5);
      expect(
          visibleFraction(note, const Rect.fromLTWH(0, 150, 400, 800)), 0.25);
    });

    test('is 0 when the circle is out of sight', () {
      expect(visibleFraction(note, const Rect.fromLTWH(0, 300, 400, 800)), 0);
      expect(visibleFraction(note, const Rect.fromLTWH(0, -400, 400, 300)), 0);
    });
  });
}
