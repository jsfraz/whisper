/// Playback speeds the voice player cycles through.
const List<double> playbackSpeeds = [1.0, 1.5, 2.0];

/// Next speed in the cycle; an unknown value falls back to the first one.
double nextSpeed(double current) {
  final index = playbackSpeeds.indexOf(current);
  return playbackSpeeds[(index + 1) % playbackSpeeds.length];
}

/// Label of the cycle button: `1x`, `1.5x`, `2x`.
String speedLabel(double speed) {
  return speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';
}
