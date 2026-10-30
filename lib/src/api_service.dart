import "dart:convert";
import "dart:io";

import "package:dart_api_service/dart_api_service.dart";
import "package:http/http.dart" as http;
import "package:meta/meta.dart";

/// The base implementation of the API service.
class HttpApiService<DefaultRepresentation extends Object> {
  /// Create the HttpApiService
  HttpApiService({
    required this._baseUrl,
    this.authenticationService = const EmptyAuthService(),
    ApiConverter<DefaultRepresentation, DefaultRepresentation>? apiResponseConverter,
    this._defaultHeaders = const {},
    this._defaultQueryParameters = const {},
    this.allResponsesAllowed = false,
    http.Client? client,
  }) : _apiResponseConverter = apiResponseConverter ?? NonConverter<DefaultRepresentation>(),
       _client = client ?? http.Client();

  /// Creates an [HttpApiService] whose client is a [MockHttpClient] that
  /// answers requests using the given [mocks], without any mocking library.
  ///
  /// Every entry in [mocks] receives a service with the same configuration
  /// (base URL, default headers, ...) so mocks can be defined with the same
  /// syntax as regular calls:
  ///
  /// ```dart
  /// final service = HttpApiService.mocked(
  ///   baseUrl: Uri.parse("https://test.com"),
  ///   mocks: [
  ///     (service) => service
  ///         .endpoint("/test/:id")
  ///         .withVariables({"id": "1"})
  ///         .getMocker()
  ///         .returns((request) => jsonEncode({
  ///               "something": request.queryParameters["test"],
  ///             })),
  ///   ],
  /// );
  /// ```
  ///
  /// Requests that match no mock are delegated to [fallbackClient]. Without a
  /// fallback they fail with an [ApiConnectionFailureException] containing the
  /// reason no mock could be resolved.
  factory HttpApiService.mocked({
    required Uri baseUrl,
    required List<MockDefinition Function(HttpApiService<DefaultRepresentation>)> mocks,
    http.Client? fallbackClient,
    AuthenticationService authenticationService = const EmptyAuthService(),
    ApiConverter<DefaultRepresentation, DefaultRepresentation>? apiResponseConverter,
    Map<String, String> defaultHeaders = const {},
    Map<String, String> defaultQueryParameters = const {},
    bool allResponsesAllowed = false,
  }) {
    final client = MockHttpClient(fallbackClient: fallbackClient);
    final service = HttpApiService<DefaultRepresentation>(
      baseUrl: baseUrl,
      authenticationService: authenticationService,
      apiResponseConverter: apiResponseConverter,
      defaultHeaders: defaultHeaders,
      defaultQueryParameters: defaultQueryParameters,
      allResponsesAllowed: allResponsesAllowed,
      client: client,
    );
    client.addAll([for (final mock in mocks) mock(service)]);
    return service;
  }

  final ApiConverter<DefaultRepresentation, DefaultRepresentation> _apiResponseConverter;
  final Uri _baseUrl;

  /// The authentication service used to retrieve credentials.
  final AuthenticationService authenticationService;

  /// Whether endpoints created by this service accept responses with a status
  /// code of 400 or above as successful.
  ///
  /// By default these responses result in an [ApiResponseException]. When this
  /// is `true` that check is bypassed and every response is passed to the
  /// converter. The user is then responsible for handling error responses and
  /// differing body structures in their converters, as an error body will
  /// generally not have the same structure as a successful body.
  ///
  /// Can be overridden per endpoint with
  /// [Endpoint.withAllResponsesAllowed].
  final bool allResponsesAllowed;
  final Map<String, String> _defaultHeaders;
  final Map<String, String> _defaultQueryParameters;
  final http.Client _client;

  /// The base URL of the API service.
  Uri get baseUrl => _baseUrl;

  /// The HTTP client used to make requests.
  http.Client get client => _client;

  /// Create a callable endpoint.
  ///
  /// Represents an accessible web endpoint.
  Endpoint<DefaultRepresentation, DefaultRepresentation> endpoint(
    String path,
  ) => Endpoint._(
    endpoint: _baseUrl.replace(path: path),
    defaultQueryParameter: _defaultQueryParameters,
    converter: _apiResponseConverter,
    apiService: this,
    defaultHeaders: _defaultHeaders,
    allResponsesAllowed: allResponsesAllowed,
  );

  TaskEither<ApiException, http.Response> _request(
    Uri endpoint,
    RequestMethod method, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool isAuthenticated = false,
  }) => .Do(($) async {
    TaskEither<ApiException, http.Response> makeRequest() => .Do(($) async {
      var headersWithAuth = headers ?? {};
      if (isAuthenticated) {
        final credentials = await $(
          _credentials(authenticationService.getCredentials),
        );
        headersWithAuth = {...headersWithAuth, ...credentials.headers};
      }

      Future<http.Response> wrapHttpCall(
        Future<http.Response> Function() callable,
      ) => $(
        .tryCatch(callable, (error, _) {
          if (error is SocketException) {
            return ApiConnectionFailureException(reason: error.message);
          }
          return const ApiCallFailedException();
        }),
      );

      return switch (method) {
        RequestMethod.delete => wrapHttpCall(
          () => _client.delete(
            endpoint,
            headers: headersWithAuth,
            body: body,
            encoding: encoding,
          ),
        ),
        RequestMethod.get => wrapHttpCall(
          () => _client.get(endpoint, headers: headersWithAuth),
        ),
        RequestMethod.patch => wrapHttpCall(
          () => _client.patch(
            endpoint,
            headers: headersWithAuth,
            body: body,
            encoding: encoding,
          ),
        ),
        RequestMethod.post => wrapHttpCall(
          () => _client.post(
            endpoint,
            headers: headersWithAuth,
            body: body,
            encoding: encoding,
          ),
        ),
        RequestMethod.put => wrapHttpCall(
          () => _client.put(
            endpoint,
            headers: headersWithAuth,
            body: body,
            encoding: encoding,
          ),
        ),
      };
    });

    var response = await $(makeRequest());

    if (response.statusCode == 401 && isAuthenticated) {
      final refreshed = await authenticationService.refreshCredentials().run();
      if (refreshed.isLeft()) {
        return response;
      }

      response = await $(makeRequest());
    }

    return response;
  });

  TaskEither<ApiException, AuthCredentials> _credentials(
    TaskEither<CredentialRetrievalFailedException, AuthCredentials> Function() retrieve,
  ) => retrieve().mapLeft(ApiAuthenticationFailedException.new);

  TaskEither<ApiException, http.Response> _upload({
    required Uri endpoint,
    required String fieldName,
    required List<int> fileBytes,
    required String fileName,
    required RequestMethod method,
    Map<String, String>? fields,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    bool isAuthenticated = false,
  }) => .Do(($) async {
    final uploadEndpoint = endpoint.replace(
      queryParameters: {..._defaultQueryParameters, ...?queryParameters},
    );
    final request = http.MultipartRequest(
      method.name.toUpperCase(),
      uploadEndpoint,
    );
    final allHeaders = {...?headers};

    if (isAuthenticated) {
      final credentials = await $(
        _credentials(authenticationService.getCredentials),
      );
      allHeaders.addAll(credentials.headers);
    }
    request.headers.addAll(allHeaders);

    if (fields != null) {
      request.fields.addAll(fields);
    }

    request.files.add(
      http.MultipartFile.fromBytes(fieldName, fileBytes, filename: fileName),
    );

    return $(
      .tryCatch(
        () async => http.Response.fromStream(await _client.send(request)),
        (error, _) => error is SocketException
            ? ApiConnectionFailureException(reason: error.message)
            : const ApiCallFailedException(),
      ),
    );
  });
}

/// A representation of an accessible web endpoint from which data
/// can be retrieved
class Endpoint<ResponseModel, RequestModel> {
  /// Mark this endpoint as needing authentication
  ///
  /// This will cause the service to retrieve the [AuthCredentials] when trying
  /// to execute this endpoint
  const Endpoint._({
    required this._endpoint,
    required this._converter,
    required this._apiService,
    this._defaultHeaders = const {},
    Map<String, String> defaultQueryParameter = const {},
    this._authenticated = false,
    this._allResponsesAllowed = false,
  }) : _defaultQueryParameters = defaultQueryParameter;

  final Uri _endpoint;
  final HttpApiService _apiService;
  final bool _authenticated;
  final bool _allResponsesAllowed;
  final Map<String, String> _defaultHeaders;
  final Map<String, String> _defaultQueryParameters;
  final ApiConverter<ResponseModel, RequestModel> _converter;

  /// get the currently set path.
  String get path => _endpoint.path;

  /// Executes a multipart POST request for file uploading.
  /// This method is used to upload files to the server.
  TaskEither<ApiException, ApiResponse<ResponseModel>> upload({
    required String fieldName,
    required List<int> fileBytes,
    required String fileName,
    RequestMethod method = RequestMethod.post,
    Map<String, String>? fields,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
  }) => _apiService
      ._upload(
        endpoint: _endpoint,
        fieldName: fieldName,
        fileBytes: fileBytes,
        fileName: fileName,
        method: method,
        fields: fields,
        headers: {..._defaultHeaders, ...?headers},
        queryParameters: {..._defaultQueryParameters, ...?queryParameters},
        isAuthenticated: _authenticated,
      )
      .flatMap((response) => .fromEither(_toApiResponse(response)));

  Either<ApiException, ApiResponse<ResponseModel>> _toApiResponse(
    http.Response response,
  ) {
    if (!_allResponsesAllowed && response.statusCode >= 400) {
      return .left(ApiResponseException(inner: response));
    }

    return _converter.toRepresentation(response.body).map((result) => ApiResponse(inner: response, result: result));
  }

  /// Created a new endpoint from this endpoint.
  Endpoint<ResponseModel, RequestModel> child(String path) {
    final newPath = "${_endpoint.path}$path";
    return Endpoint._(
      endpoint: _endpoint.replace(path: newPath),
      converter: _converter,
      apiService: _apiService,
      authenticated: _authenticated,
      defaultHeaders: _defaultHeaders,
      defaultQueryParameter: _defaultQueryParameters,
      allResponsesAllowed: _allResponsesAllowed,
    );
  }

  /// Add to the existing default headers.
  ///
  /// This does override existing headers of the same name.
  Endpoint<ResponseModel, RequestModel> addHeaders(
    Map<String, String> headers,
  ) => setDefaultHeaders({..._defaultHeaders, ...headers});

  /// Set the default headers
  Endpoint<ResponseModel, RequestModel> setDefaultHeaders(
    Map<String, String> headers,
  ) => Endpoint._(
    endpoint: _endpoint,
    converter: _converter,
    apiService: _apiService,
    authenticated: _authenticated,
    defaultHeaders: headers,
    defaultQueryParameter: _defaultQueryParameters,
    allResponsesAllowed: _allResponsesAllowed,
  );

  /// Add to existing default query parameters
  ///
  /// This does override existing query parameters of the same name.
  Endpoint<ResponseModel, RequestModel> addDefaultQueryParameters(
    Map<String, String> queryParameters,
  ) => setDefaultQueryParameters({
    ..._defaultQueryParameters,
    ...queryParameters,
  });

  /// Set the default query parameters
  Endpoint<ResponseModel, RequestModel> setDefaultQueryParameters(
    Map<String, String> queryParameters,
  ) => Endpoint._(
    endpoint: _endpoint,
    converter: _converter,
    apiService: _apiService,
    authenticated: _authenticated,
    defaultHeaders: _defaultHeaders,
    defaultQueryParameter: queryParameters,
    allResponsesAllowed: _allResponsesAllowed,
  );

  /// Binds variables to paths.
  ///
  /// You can use variables formatted as such when creating an endpoint:
  ///
  /// `/api/users/:userId/test/:replacement`
  ///
  /// This method can be used like this, given the above endpoint definition:
  ///
  /// ```dart
  /// endpoint.withVariables({
  ///   "userId": 1,
  ///   "replacement": "something",
  /// });
  ///
  /// print(endpoint.path); // shows: /api/users/1/test/something
  /// ```
  ///
  Endpoint<ResponseModel, RequestModel> withVariables(
    Map<String, dynamic> variables,
  ) {
    final newPath = variables.entries.fold(
      _endpoint.path,
      (previousValue, element) => previousValue.replaceAll(":${element.key}", "${element.value}"),
    );
    return Endpoint._(
      endpoint: _endpoint.replace(path: newPath),
      converter: _converter,
      apiService: _apiService,
      authenticated: _authenticated,
      defaultHeaders: _defaultHeaders,
      defaultQueryParameter: _defaultQueryParameters,
      allResponsesAllowed: _allResponsesAllowed,
    );
  }

  /// Sets whether responses with a status code of 400 or above are accepted.
  ///
  /// By default these responses result in an [ApiResponseException]. When
  /// [allowed] is `true` that check is bypassed and every response is passed
  /// to the converter. This means the user is responsible for handling error
  /// responses and differing body structures in their converters, as an error
  /// body will generally not have the same structure as a successful body.
  ///
  /// This overrides [HttpApiService.allResponsesAllowed] for this endpoint.
  Endpoint<ResponseModel, RequestModel> withAllResponsesAllowed({
    bool allowed = true,
  }) => Endpoint._(
    endpoint: _endpoint,
    apiService: _apiService,
    converter: _converter,
    authenticated: _authenticated,
    defaultHeaders: _defaultHeaders,
    defaultQueryParameter: _defaultQueryParameters,
    allResponsesAllowed: allowed,
  );

  /// Creates a mocker for GET requests to this endpoint.
  EndpointMocker getMocker() => _mocker(RequestMethod.get);

  /// Creates a mocker for POST requests to this endpoint.
  EndpointMocker postMocker() => _mocker(RequestMethod.post);

  /// Creates a mocker for PUT requests to this endpoint.
  EndpointMocker putMocker() => _mocker(RequestMethod.put);

  /// Creates a mocker for PATCH requests to this endpoint.
  EndpointMocker patchMocker() => _mocker(RequestMethod.patch);

  /// Creates a mocker for DELETE requests to this endpoint.
  EndpointMocker deleteMocker() => _mocker(RequestMethod.delete);

  EndpointMocker _mocker(RequestMethod method) => EndpointMocker(endpoint: _endpoint, method: method);

  /// Marks that this method requires authentication to execute.
  Endpoint<ResponseModel, RequestModel> authenticate() => Endpoint._(
    endpoint: _endpoint,
    apiService: _apiService,
    converter: _converter,
    authenticated: true,
    defaultHeaders: _defaultHeaders,
    defaultQueryParameter: _defaultQueryParameters,
    allResponsesAllowed: _allResponsesAllowed,
  );

  /// Add a response converter to more easily handle response conversion
  Endpoint<AResponse, ARequest> withConverter<AResponse, ARequest>(
    ApiConverter<AResponse, ARequest> converter,
  ) => Endpoint._(
    endpoint: _endpoint,
    converter: converter,
    apiService: _apiService,
    authenticated: _authenticated,
    defaultHeaders: _defaultHeaders,
    defaultQueryParameter: _defaultQueryParameters,
    allResponsesAllowed: _allResponsesAllowed,
  );

  /// Change the multiplicity of the endpoint
  Endpoint<AResponse, ARequest> changeMultiplicity<AResponse, ARequest>(
    ApiConverter<AResponse, ARequest> Function(
      MultiplicitySupportedConverter<ResponseModel, RequestModel> converter,
    )
    changer,
  ) => withConverter(
    changer(
      _converter as MultiplicitySupportedConverter<ResponseModel, RequestModel>,
    ),
  );

  /// Execute a GET request.
  TaskEither<ApiException, ApiResponse<ResponseModel>> get({
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/>? queryParameters,
    RequestModel? requestModel,
    Encoding? encoding,
  }) => _request(
    requestMethod: RequestMethod.get,
    headers: headers,
    queryParameters: queryParameters,
    requestModel: requestModel,
    encoding: encoding,
  );

  /// Execute a DELETE request.
  TaskEither<ApiException, ApiResponse<ResponseModel>> delete({
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/>? queryParameters,
    RequestModel? requestModel,
    Encoding? encoding,
  }) => _request(
    requestMethod: RequestMethod.delete,
    headers: headers,
    queryParameters: queryParameters,
    requestModel: requestModel,
    encoding: encoding,
  );

  /// Execute a PATCH request.
  TaskEither<ApiException, ApiResponse<ResponseModel>> patch({
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/>? queryParameters,
    RequestModel? requestModel,
    Encoding? encoding,
  }) => _request(
    requestMethod: RequestMethod.patch,
    headers: headers,
    queryParameters: queryParameters,
    requestModel: requestModel,
    encoding: encoding,
  );

  /// Execute a POST request.
  TaskEither<ApiException, ApiResponse<ResponseModel>> post({
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/>? queryParameters,
    RequestModel? requestModel,
    Encoding? encoding,
  }) => _request(
    requestMethod: RequestMethod.post,
    headers: headers,
    queryParameters: queryParameters,
    requestModel: requestModel,
    encoding: encoding,
  );

  /// Execute a PUT request.
  TaskEither<ApiException, ApiResponse<ResponseModel>> put({
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/>? queryParameters,
    RequestModel? requestModel,
    Encoding? encoding,
  }) => _request(
    requestMethod: RequestMethod.put,
    headers: headers,
    requestModel: requestModel,
    queryParameters: queryParameters,
    encoding: encoding,
  );

  TaskEither<ApiException, ApiResponse<ResponseModel>> _request({
    required RequestMethod requestMethod,
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/>? queryParameters,
    RequestModel? requestModel,
    Encoding? encoding,
  }) {
    final endpoint = _endpoint.replace(
      queryParameters: {..._defaultQueryParameters, ...?queryParameters},
    );

    final bodyResult = requestModel == null
        ? Either<ApiException, Object?>.of(null)
        : _converter.fromRepresentation(requestModel);

    return TaskEither<ApiException, Object?>.fromEither(bodyResult).flatMap(
      (body) => _apiService
          ._request(
            endpoint,
            requestMethod,
            headers: {..._defaultHeaders, ...?headers},
            body: body,
            encoding: encoding,
            isAuthenticated: _authenticated,
          )
          .flatMap((response) => .fromEither(_toApiResponse(response))),
    );
  }
}

/// Base Exception thrown when an api call goes wrong
sealed class const ApiException() {
  /// Constructs the exception
  this;
}

/// Exception returned when a response body could not be converted
final class RequestObjectSerializationApiException extends ApiException {
  /// Creates the exception
  const RequestObjectSerializationApiException({this.error, this.stackTrace});

  /// The error that occurred in the conversion.
  final Object? error;

  /// The stacktrace of the error.
  final StackTrace? stackTrace;
}

/// Exception returned when a request object could not be converted
final class ResponseObjectSerializationApiException extends ApiException {
  /// Creates the exception
  const ResponseObjectSerializationApiException({this.error, this.stackTrace});

  /// The error that occurred in the conversion.
  final Object? error;

  /// The stacktrace of the error.
  final StackTrace? stackTrace;
}

/// Exception thrown when the api call results in a connection failure
final class const ApiConnectionFailureException({this.reason}) extends ApiException {
  ///
  this;

  /// The reason the connection failed, if known.
  final String? reason;
}

/// Exception thrown when the api call results in a generic failure
final class const ApiCallFailedException() extends ApiException {
  ///
  this;
}

/// Exception returned when the credentials could not be retrieved
final class const ApiAuthenticationFailedException(this.inner) extends ApiException {
  ///
  this;

  /// The failure reported by the authentication service.
  final CredentialRetrievalFailedException inner;
}

/// Exception returned when the Api call resulted in an error response or
/// the response could not be converted
final class ApiResponseException extends ApiException {
  /// Creates an API Exception
  const ApiResponseException({
    required this.inner,
    this.error,
    this.stackTrace,
  });

  /// the http status code that resulted from a request
  int get statusCode => inner.statusCode;

  /// the [http] response.
  ///
  /// This is still provided to ensure that gaps in functionality do not cause
  /// wait times in the development cycle of this package.
  final http.Response inner;

  /// The error, if any occurred in the parsing of the object
  final Object? error;

  /// The stacktrace of the error.
  final StackTrace? stackTrace;

  @override
  String toString() =>
      "ApiException: ${inner.request?.url} -> $statusCode. "
      "\ndetails: $error\n$stackTrace";
}

/// A response representation of the API call.
class ApiResponse<Model> {
  /// Create an API response
  @visibleForTesting
  const ApiResponse({required this.inner, this.result});

  /// the http status code that resulted from a request
  int get statusCode => inner.statusCode;

  /// the [http] response.
  ///
  /// This is still provided to ensure that gaps in functionality do not cause
  /// wait times in the development cycle of this package.
  final http.Response inner;

  /// The representable object of the result.
  final Model? result;
}
