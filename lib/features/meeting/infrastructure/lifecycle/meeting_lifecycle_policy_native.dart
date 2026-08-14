import 'package:flutter/widgets.dart';

/// Native lifecycle changes retain the existing camera suspend/resume policy.
bool shouldForwardMeetingLifecycle(AppLifecycleState state) => true;
