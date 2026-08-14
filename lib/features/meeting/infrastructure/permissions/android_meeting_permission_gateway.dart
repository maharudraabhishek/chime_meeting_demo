import 'package:flutter/services.dart';

import '../../domain/entities/meeting_failure.dart';
import '../../domain/entities/meeting_result.dart';
import '../../domain/gateways/meeting_permission_gateway.dart';

/// Android implementation of the meeting media-permission boundary.
///
/// The native activity owns the Android permission lifecycle. This adapter only
/// invokes that boundary and converts platform failures into safe domain values.
final class AndroidMeetingPermissionGateway
    implements MeetingPermissionGateway {
  AndroidMeetingPermissionGateway({MethodChannel? methodChannel})
    : _methodChannel =
          methodChannel ?? const MethodChannel(_permissionChannelName);

  static const String _permissionChannelName =
      'com.example.chimemeeting/permissions/methods';
  static const String _requestPermissionsMethod = 'requestMeetingPermissions';
  static const String _getPermissionStatusMethod = 'getMeetingPermissionStatus';
  static const String _openAppSettingsMethod = 'openAppSettings';

  final MethodChannel _methodChannel;

  @override
  Future<MeetingResult<MeetingPermissionStatus>>
  requestRequiredPermissions() async {
    try {
      final status = await _methodChannel.invokeMethod<String>(
        _requestPermissionsMethod,
      );
      if (status == null) {
        return const MeetingError<MeetingPermissionStatus>(
          MeetingFailure(MeetingFailureType.platformBridge),
        );
      }
      return MeetingSuccess<MeetingPermissionStatus>(_mapStatus(status));
    } on MissingPluginException {
      return const MeetingError<MeetingPermissionStatus>(
        MeetingFailure(MeetingFailureType.platformBridge),
      );
    } on PlatformException {
      return const MeetingError<MeetingPermissionStatus>(
        MeetingFailure(MeetingFailureType.platformBridge),
      );
    }
  }

  @override
  Future<MeetingResult<MeetingPermissionStatus>>
  getRequiredPermissionStatus() async {
    try {
      final status = await _methodChannel.invokeMethod<String>(
        _getPermissionStatusMethod,
      );
      if (status == null) {
        return const MeetingError<MeetingPermissionStatus>(
          MeetingFailure(MeetingFailureType.platformBridge),
        );
      }
      return MeetingSuccess<MeetingPermissionStatus>(_mapStatus(status));
    } on MissingPluginException {
      return const MeetingError<MeetingPermissionStatus>(
        MeetingFailure(MeetingFailureType.platformBridge),
      );
    } on PlatformException {
      return const MeetingError<MeetingPermissionStatus>(
        MeetingFailure(MeetingFailureType.platformBridge),
      );
    }
  }

  @override
  Future<MeetingResult<bool>> openAppSettings() async {
    try {
      final launched = await _methodChannel.invokeMethod<bool>(
        _openAppSettingsMethod,
      );
      if (launched == null) {
        return const MeetingError<bool>(
          MeetingFailure(MeetingFailureType.platformBridge),
        );
      }
      return MeetingSuccess<bool>(launched);
    } on MissingPluginException {
      return const MeetingError<bool>(
        MeetingFailure(MeetingFailureType.platformBridge),
      );
    } on PlatformException {
      return const MeetingError<bool>(
        MeetingFailure(MeetingFailureType.platformBridge),
      );
    }
  }

  MeetingPermissionStatus _mapStatus(String status) {
    switch (status) {
      case 'granted':
        return MeetingPermissionStatus.granted;
      case 'permanentlyDenied':
        return MeetingPermissionStatus.permanentlyDenied;
      default:
        return MeetingPermissionStatus.denied;
    }
  }
}
