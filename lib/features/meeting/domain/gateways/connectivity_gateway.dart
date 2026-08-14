/// Provides a point-in-time network preflight check for meeting bootstrap.
///
/// The meeting feature decides whether a backend or Chime session can begin
/// without leaking platform-specific connectivity APIs into presentation code.
abstract interface class ConnectivityGateway {
  /// Returns whether the device currently has a usable network transport.
  Future<bool> get isOnline;
}
