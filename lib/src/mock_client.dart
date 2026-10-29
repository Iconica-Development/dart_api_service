import "dart:async";
import "dart:convert";
import "dart:io";

import "package:dart_api_service/src/request_method.dart";
import "package:http/http.dart" as http;

/// A handler producing the [MockResponse] for a [MockRequest].
typedef MockResponseHandler = FutureOr<MockResponse> Function(
  MockRequest request,
);

/// The request as received by a mock.
class MockRequest {
  /// Creates a mock request
  const MockRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.bodyBytes,
  });

  /// The method of the request.
  final RequestMethod method;

  /// The full uri of the request.
  final Uri uri;

  /// The headers sent with the request.
  final Map<String, String> headers;

  /// The raw body of the request.
  final List<int> bodyBytes;

  /// The query parameters of the request.
  Map<String, String> get queryParameters => uri.queryParameters;

  /// The body of the request decoded as UTF-8.
  String get body => utf8.decode(bodyBytes, allowMalformed: true);
}

/// The response a mock answers with.
class MockResponse {
  /// Creates a mock response
  const MockResponse({
    this.body = "",
    this.statusCode = 200,
    this.headers = const {},
  });

  /// The body of the response.
  final String body;

  /// The status code of the response.
  final int statusCode;

  /// The headers of the response.
  final Map<String, String> headers;
}

/// Creates a [MockDefinition] for a single method on a single path.
///
/// Obtained through `Endpoint.getMocker()`, `postMocker()`, etc.
class EndpointMocker {
  /// Creates a mocker for the [method] on the [endpoint].
  const EndpointMocker({required this.endpoint, required this.method});

  /// The endpoint that is mocked.
  final Uri endpoint;

  /// The method that is mocked.
  final RequestMethod method;

  /// Answers with the body returned by [body], with the given [statusCode].
  MockDefinition returns(
    FutureOr<String> Function(MockRequest request) body, {
    int statusCode = 200,
    Map<String, String> headers = const {},
  }) => respondsWith(
    (request) async => MockResponse(
      body: await body(request),
      statusCode: statusCode,
      headers: headers,
    ),
  );

  /// Answers with the full [MockResponse] returned by [handler].
  MockDefinition respondsWith(MockResponseHandler handler) =>
      MockDefinition(endpoint: endpoint, method: method, handler: handler);
}

/// A mocked method and path combined with the handler answering it.
class MockDefinition {
  /// Creates a mock definition
  const MockDefinition({
    required this.endpoint,
    required this.method,
    required this.handler,
  });

  /// The endpoint this mock answers.
  ///
  /// Path segments starting with `:` that have not been bound using
  /// `withVariables` match any value.
  final Uri endpoint;

  /// The method this mock answers.
  final RequestMethod method;

  /// The handler producing the response.
  final MockResponseHandler handler;

  /// Whether this mock answers the given [request].
  bool matches(http.BaseRequest request) {
    if (request.method.toUpperCase() != method.name.toUpperCase()) {
      return false;
    }
    final url = request.url;
    if (url.scheme != endpoint.scheme ||
        url.host != endpoint.host ||
        url.port != endpoint.port) {
      return false;
    }

    final expected = _segments(endpoint);
    final actual = _segments(url);
    if (expected.length != actual.length) return false;

    for (var i = 0; i < expected.length; i++) {
      final isVariable = expected[i].startsWith(":");
      if (!isVariable && expected[i] != actual[i]) return false;
    }
    return true;
  }

  List<String> _segments(Uri uri) {
    final segments = [...uri.pathSegments];
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    return segments;
  }
}

/// An [http.Client] answering requests from [MockDefinition]s, without relying
/// on a mocking library so it can be used in release builds.
///
/// The first definition matching a request answers it. Requests matching no
/// definition are delegated to the fallback client. Without a fallback they
/// fail with a [SocketException] describing why no mock could be resolved,
/// which the api service reports as an `ApiConnectionFailureException`.
class MockHttpClient extends http.BaseClient {
  /// Creates a mock client.
  MockHttpClient({
    Iterable<MockDefinition> mocks = const [],
    this.fallbackClient,
  }) : _mocks = [...mocks];

  /// The client receiving requests that no mock answers.
  final http.Client? fallbackClient;

  final List<MockDefinition> _mocks;

  /// Adds a mock to this client.
  void add(MockDefinition mock) => _mocks.add(mock);

  /// Adds multiple mocks to this client.
  void addAll(Iterable<MockDefinition> mocks) => _mocks.addAll(mocks);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final mock = _mocks.where((mock) => mock.matches(request)).firstOrNull;

    if (mock == null) {
      final fallback = fallbackClient;
      if (fallback != null) return fallback.send(request);

      throw SocketException(
        "No mock resolved ${request.method} ${request.url} and no fallback "
        "client was supplied. Registered mocks: "
        "${_mocks.isEmpty ? "none" : _mocks.map(_describe).join(", ")}",
      );
    }

    final bodyBytes = await request.finalize().toBytes();
    final response = await mock.handler(
      MockRequest(
        method: mock.method,
        uri: request.url,
        headers: request.headers,
        bodyBytes: bodyBytes,
      ),
    );

    final responseBytes = utf8.encode(response.body);
    return http.StreamedResponse(
      Stream.value(responseBytes),
      response.statusCode,
      contentLength: responseBytes.length,
      request: request,
      headers: response.headers,
    );
  }

  String _describe(MockDefinition mock) =>
      "${mock.method.name.toUpperCase()} ${mock.endpoint.path}";

  @override
  void close() => fallbackClient?.close();
}
