/// A safe exception emitted by the application's infrastructure boundary.
///
/// These exceptions intentionally carry categories rather than raw response
/// bodies or credentials. The repository translates them into domain failures
/// before they can reach presentation code.
sealed class AppException implements Exception {
  const AppException();
}

/// The request could not reach the remote service.
final class NetworkException extends AppException {
  const NetworkException();
}

/// The request exceeded the centrally configured deadline.
final class RequestTimeoutException extends AppException {
  const RequestTimeoutException();
}

/// The server returned a non-successful HTTP or API-envelope status.
final class ApiException extends AppException {
  const ApiException({
    required this.statusCode,
    this.errorCode,
    this.resultCategory,
    this.requestId,
  });

  final int statusCode;
  final String? errorCode;
  final String? resultCategory;
  final String? requestId;
}

/// The service response could not be decoded into the documented contract.
final class InvalidResponseException extends AppException {
  const InvalidResponseException();
}

/// Required build-time configuration is absent or invalid.
final class AppConfigurationException extends AppException {
  const AppConfigurationException([this.message]);

  final String? message;
}

/// An unclassified infrastructure error occurred.
final class UnexpectedInfrastructureException extends AppException {
  const UnexpectedInfrastructureException();
}
