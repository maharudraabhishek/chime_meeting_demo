import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'app/app.dart';
import 'app/di/dependency_container.dart';
import 'core/error/app_exception.dart';
import 'features/meeting/presentation/bloc/meeting_bloc.dart';

/// Boots Flutter, composes dependencies, and installs crash-safe error
/// reporting in the same Dart zone used by [runApp].
void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      final container = GetIt.instance;

      FlutterError.onError = (FlutterErrorDetails details) {
        if (kDebugMode) {
          FlutterError.presentError(details);
          _reportError(
            'Flutter',
            details.exception,
            details.stack ?? StackTrace.current,
          );
        } else {
          _reportError('Flutter', details.exception.runtimeType.toString());
        }
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        if (kDebugMode) {
          _reportError('PlatformDispatcher', error, stack);
        } else {
          _reportError('PlatformDispatcher', error.runtimeType.toString());
        }
        return true;
      };

      try {
        configureDependencies(container);
      } on AppConfigurationException catch (error, stack) {
        _reportError('Configuration', error, stack);
        runApp(const ChimeMeetingConfigurationErrorApp());
        return;
      }

      runApp(
        ChimeMeetingApp(createMeetingBloc: () => container<MeetingBloc>()),
      );
    },
    (Object error, StackTrace stack) {
      if (kDebugMode) {
        _reportError('Zone', error, stack);
      } else {
        _reportError('Zone', error.runtimeType.toString());
      }
    },
  );
}

void _reportError(String source, Object error, [StackTrace? stack]) {
  if (kDebugMode && stack != null) {
    final safeStack = stack == StackTrace.empty ? StackTrace.current : stack;

    debugPrint('[$source] ${error.runtimeType}: $error');
    debugPrintStack(stackTrace: safeStack, label: source);
    return;
  }

  // Release output intentionally excludes raw exception bodies/stacks.
  debugPrint('[$source] $error');
}
