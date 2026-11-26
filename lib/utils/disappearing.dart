import 'package:easy_localization/easy_localization.dart';

/// Timers a chat can agree on: an hour, a day, a week. [0] turns the timer off.
const List<int> disappearingOptions = [3600, 86400, 604800, 0];

/// Compact label of a timer in seconds, e.g. "1 h", "24 h", "7 d".
String disappearingLabel(int seconds) {
  if (seconds <= 0) {
    return 'disappearingOff'.tr();
  }
  if (seconds % 86400 == 0) {
    return '${seconds ~/ 86400} d';
  }
  if (seconds % 3600 == 0) {
    return '${seconds ~/ 3600} h';
  }
  return '${seconds ~/ 60} min';
}
