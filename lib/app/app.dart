import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/meeting/presentation/bloc/meeting_bloc.dart';
import '../features/meeting/presentation/pages/meeting_flow_page.dart';

/// Root widget that owns the presentation-scoped [MeetingBloc] lifecycle.
final class ChimeMeetingApp extends StatelessWidget {
  const ChimeMeetingApp({required this.createMeetingBloc, super.key});

  final MeetingBloc Function() createMeetingBloc;

  /// Builds the application theme and presentation-scoped BLoC provider.
  @override
  Widget build(BuildContext context) {
    return BlocProvider<MeetingBloc>(
      create: (_) => createMeetingBloc(),
      child: MaterialApp(
        title: 'Chime Meeting',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        home: const MeetingFlowPage(),
      ),
    );
  }
}

/// Draws a safe first frame when required public build configuration is absent.
///
/// This prevents Android from waiting indefinitely on Flutter's first frame and
/// does not expose exception details or server-side credentials.
final class ChimeMeetingConfigurationErrorApp extends StatelessWidget {
  const ChimeMeetingConfigurationErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chime Meeting',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.settings_outlined, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'App configuration required',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Rebuild with a valid HTTPS MEETING_API_BASE_URL.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
