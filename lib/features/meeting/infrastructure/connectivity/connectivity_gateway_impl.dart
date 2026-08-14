import 'package:connectivity_plus/connectivity_plus.dart';

import '../../domain/gateways/connectivity_gateway.dart';

/// Wraps the platform connectivity plugin behind the meeting feature boundary.
///
/// This adapter intentionally performs a single check against the device's
/// current transport state; it does not subscribe to network changes or manage
/// background connectivity state.
final class ConnectivityGatewayImpl implements ConnectivityGateway {
  ConnectivityGatewayImpl({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return results.isNotEmpty &&
        results.any((result) => result != ConnectivityResult.none);
  }
}
