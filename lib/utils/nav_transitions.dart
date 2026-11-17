import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';

/// Shared navigation timing: fast start, soft landing.
const Duration navDuration = Duration(milliseconds: 200);
const Curve navCurve = Curves.easeOutCubic;

/// Opens a conversation: the new page rises from the bottom.
///
/// Deliberately not `bottomToTopJoined` — the joined variants need the
/// previous page as a widget and mount it a second time, which restarts its
/// `initState` (cache scans, network calls) while the transition animates.
Route<void> slideUpRoute(Widget child) {
  return PageTransition(
    type: PageTransitionType.bottomToTop,
    child: child,
    duration: navDuration,
    reverseDuration: navDuration,
    curve: navCurve,
  );
}

/// Opens a secondary page: the content cross-fades, nothing large slides.
Route<void> fadeRoute(Widget child) {
  return PageTransition(
    type: PageTransitionType.fade,
    child: child,
    duration: navDuration,
    reverseDuration: navDuration,
    curve: navCurve,
  );
}

/// Opens the next step of a flow (forwarding, onboarding): it comes in from
/// the side, the way a form usually does.
Route<T> stepRoute<T>(Widget child) {
  return PageTransition<T>(
    type: PageTransitionType.rightToLeft,
    child: child,
    duration: navDuration,
    reverseDuration: navDuration,
    curve: navCurve,
  );
}
