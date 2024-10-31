import "dart:async";

/// A service that allows the api service to obtain AuthenticationInformation
abstract class AuthenticationService<T extends AuthCredentials> {
  /// Never call this...
  const AuthenticationService();

  /// Returns the current credentials
  FutureOr<T> getCredentials();

  /// Refreshes the credentials.
  ///
  /// If you want to apply custom refresh logic
  /// you can override this function. By default it will try to retrieve the
  /// credentials without any refresh information.
  FutureOr<T> refreshCredentials() => getCredentials();
}

/// A generic interface to define AuthCredentials;
abstract interface class AuthCredentials {
  /// returns the auth headers, mainly used in the api_service.
  Map<String, String> get headers;
}

/// Simple service always returning an instance of [EmptyAuth]
class EmptyAuthService extends AuthenticationService<EmptyAuth> {
  /// creates an empty auth service
  const EmptyAuthService();
  @override
  FutureOr<EmptyAuth> getCredentials() => EmptyAuth();
}

/// Default no auth credentials if none are provided
class EmptyAuth implements AuthCredentials {
  @override
  Map<String, String> get headers => {};
}

/// A representation of the JWT token response.
class JWTAuthCredentials implements AuthCredentials {
  /// Creates a JWTAuthCredentials object
  const JWTAuthCredentials({
    required this.refreshToken,
    required this.accessToken,
  });

  /// Creates a JWTAuthCredentials from a Map.
  ///
  /// This uses a snake_case naming convention. If your map does not conform to
  /// this, please use the standard constructer.
  factory JWTAuthCredentials.fromMap(Map<String, dynamic> map) =>
      JWTAuthCredentials(
        refreshToken: map["refresh_token"],
        accessToken: map["access_token"],
      );

  /// The token from which an access token can be retrieved.
  final String refreshToken;

  /// The token which is used to authenticate with the endpoint.
  final String accessToken;

  @override
  Map<String, String> get headers => {
        "Authorization": "Bearer $accessToken",
      };
}

/// A representation of a token authentication
class TokenAuthCredentials implements AuthCredentials {
  /// Creates a tokenAuth object
  const TokenAuthCredentials({
    required this.token,
  });

  /// The token representing the access method
  final String token;

  @override
  Map<String, String> get headers => {"Authorization": "Bearer $token"};
}
