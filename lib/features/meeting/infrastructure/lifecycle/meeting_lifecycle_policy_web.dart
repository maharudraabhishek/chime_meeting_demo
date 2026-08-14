import 'package:flutter/widgets.dart';

/// Browser tab visibility is not a meeting-session lifecycle boundary.
///
/// Chime owns transport recovery. Ignoring Flutter lifecycle projections here
/// avoids stopping camera or forcing recovery merely because a tab is hidden.
bool shouldForwardMeetingLifecycle(AppLifecycleState state) => false;
