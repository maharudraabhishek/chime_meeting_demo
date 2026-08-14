import 'package:flutter/widgets.dart';

/// A small lifecycle helper that forwards AppLifecycleState changes to a callback.
///
/// Keeps lifecycle wiring out of widgets and forwards events into the BLoC.
class SimpleAppLifecycleObserver with WidgetsBindingObserver {
  SimpleAppLifecycleObserver({required this.onStateChange}) {
    WidgetsBinding.instance.addObserver(this);
  }

  final void Function(AppLifecycleState state) onStateChange;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      onStateChange(state);
    } catch (_) {
      // Swallow exceptions from user callbacks to avoid crashing the
      // framework's lifecycle thread; BLoC handlers are responsible for
      // further error handling and reporting.
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
