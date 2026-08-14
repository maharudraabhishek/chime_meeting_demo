import 'package:chime_meeting/features/meeting/domain/entities/meeting_failure.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_result.dart';
import 'package:chime_meeting/features/meeting/infrastructure/permissions/android_meeting_permission_gateway.dart';
import 'package:chime_meeting/features/meeting/domain/gateways/meeting_permission_gateway.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.permissions/methods');
  late AndroidMeetingPermissionGateway gateway;

  setUp(() {
    gateway = AndroidMeetingPermissionGateway(methodChannel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns granted when Android grants both media permissions', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'granted');

    final result = await gateway.requestRequiredPermissions();

    expect(
      result,
      const MeetingSuccess<MeetingPermissionStatus>(
        MeetingPermissionStatus.granted,
      ),
    );
  });

  test('returns denied as a normal user-denial result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'denied');

    final result = await gateway.requestRequiredPermissions();

    expect(
      result,
      const MeetingSuccess<MeetingPermissionStatus>(
        MeetingPermissionStatus.denied,
      ),
    );
  });

  test('returns permanentlyDenied when Android reports DoNotAsk', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'permanentlyDenied');

    final result = await gateway.requestRequiredPermissions();

    expect(
      result,
      const MeetingSuccess<MeetingPermissionStatus>(
        MeetingPermissionStatus.permanentlyDenied,
      ),
    );
  });

  test('maps a missing native result to a safe platform failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    final result = await gateway.requestRequiredPermissions();

    expect(
      result,
      const MeetingError<MeetingPermissionStatus>(
        MeetingFailure(MeetingFailureType.platformBridge),
      ),
    );
  });
}
