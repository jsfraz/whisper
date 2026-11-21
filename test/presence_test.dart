import 'package:flutter_test/flutter_test.dart';
import 'package:whisper/utils/presence.dart';

void main() {
  final presence = PresenceNotifier.instance;

  setUp(() {
    presence.clear();
    presence.typingTtl = const Duration(milliseconds: 20);
    presence.presenceTtl = const Duration(milliseconds: 30);
  });

  test('presence offline carries the last seen instant', () {
    presence.applyPresence('peer', online: true);
    expect(presence.isOnline('peer'), isTrue);
    expect(presence.lastSeen('peer'), isNull);

    final sawAt = DateTime(2026, 11, 21, 12, 30);
    presence.applyPresence('peer', online: false, lastSeenAt: sawAt);
    expect(presence.isOnline('peer'), isFalse);
    expect(presence.lastSeen('peer'), sawAt);
  });

  // A peer whose app was killed never announces offline, so silence has to
  // expire instead of leaving a green dot forever.
  test('an unrefreshed online expires into offline', () async {
    presence.applyPresence('peer', online: true);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(presence.isOnline('peer'), isFalse);
    expect(presence.lastSeen('peer'), isNotNull);
  });

  test('a typing hint clears itself', () async {
    presence.applyTyping('peer');
    expect(presence.isTyping('peer'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(presence.isTyping('peer'), isFalse);
  });

  test('clear drops every known peer', () {
    presence.applyPresence('peer', online: true);
    presence.applyTyping('peer');
    presence.clear();
    expect(presence.isOnline('peer'), isNull);
    expect(presence.isTyping('peer'), isFalse);
    expect(presence.lastSeen('peer'), isNull);
  });
}
