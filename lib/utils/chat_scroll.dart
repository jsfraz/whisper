/// How many of the newest messages must be rendered for the message at
/// [index] to exist in the list at all.
///
/// The rendered window is a slice of the tail, so reaching an older message
/// always means widening that slice. [margin] leaves a few messages above the
/// target, so it does not sit alone on the first line.
int windowForAddition(int messageCount, int index, {int margin = 5}) {
  final needed = messageCount - index + margin;
  if (needed < 1) {
    return 1;
  }
  return needed > messageCount ? messageCount : needed;
}

/// Next scroll offset while walking up the list towards a message that is not
/// built yet: one viewport at a time, never below the top.
double nextJumpOffset(double pixels, double viewport) {
  final next = pixels - viewport;
  if (next < 0) {
    return 0;
  }
  return next > pixels ? pixels : next;
}
