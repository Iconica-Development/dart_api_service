import "dart:convert";

import "package:dart_api_service/dart_api_service.dart";
import "package:http/http.dart" as http;
import "package:meta/meta.dart";

/// The base implementation of the API service.
class HttpApiService<DefaultRepresentation extends Object> {
  /// Create the HttpApiService
  HttpApiService({
    required Uri baseUrl,
    this.authenticationService = const EmptyAuthService(),
    ApiConverter<DefaultRepresentation, DefaultRepresentation>?
        apiResponseConverter,
    Map<String, String> defaultHeaders = const {},
    http.Client? client,
  })  : _defaultHeaders = defaultHeaders,
        _apiResponseConverter =
            apiResponseConverter ?? NonConverter<DefaultRepresentation>(),
        _baseUrl = baseUrl,
        _client = client ?? http.Client();

  final ApiConverter<DefaultRepresentation, DefaultRepresentation>
      _apiResponseConverter;
  final Uri _baseUrl;

  /// The authentication service used to retrieve credentials.
  final AuthenticationService authenticationService;
  final Map<String, String> _defaultHeaders;
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
  ) =>
      Endpoint._(
        endpoint: _baseUrl.replace(path: path),
        converter: _apiResponseConverter,
        apiService: this,
        defaultHeaders: _defaultHeaders,
      );

  Future<http.Response> _request(
    Uri endpoint,
    RequestMethod method, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool isAuthenticated = false,
  }) async {
    var headersWithAuth = headers ?? {};
    if (isAuthenticated) {
      var credentials = await authenticationService.getCredentials();
      headersWithAuth = {
        ...headersWithAuth,
        ...credentials.headers,
      };
    }

    var result = switch (method) {
      RequestMethod.delete => _client.delete(
          endpoint,
          headers: headersWithAuth,
          body: body,
          encoding: encoding,
        ),
      RequestMethod.get => _client.get(
          endpoint,
          headers: headersWithAuth,
        ),
      RequestMethod.patch => _client.patch(
          endpoint,
          headers: headersWithAuth,
          body: body,
          encoding: encoding,
        ),
      RequestMethod.post => _client.post(
          endpoint,
          headers: headersWithAuth,
          body: body,
          encoding: encoding,
        ),
      RequestMethod.put => _client.put(
          endpoint,
          headers: headersWithAuth,
          body: body,
          encoding: encoding,
        ),
    };

    return result;
  }

  Future<http.Response> _upload({
    required Uri endpoint,
    required String fieldName,
    required List<int> fileBytes,
    required String fileName,
    required RequestMethod method,
    Map<String, String>? fields,
    Map<String, String>? headers,
    bool isAuthenticated = false,
  }) async {
    var request = http.MultipartRequest(method.name.toUpperCase(), endpoint);
    var allHeaders = headers ?? {};

    if (isAuthenticated) {
      var credentials = await authenticationService.getCredentials();
      allHeaders.addAll(credentials.headers);
    }
    request.headers.addAll(allHeaders);

    if (fields != null) {
      request.fields.addAll(fields);
    }

    request.files.add(
      http.MultipartFile.fromBytes(
        fieldName,
        fileBytes,
        filename: fileName,
      ),
    );

    var streamedResponse = await _client.send(request);
    return http.Response.fromStream(streamedResponse);
  }
}

/// A representation of an accessible web endpoint from which data
/// can be retrieved
class Endpoint<ResponseModel, RequestModel> {
  /// Mark this endpoint as needing authentication
  ///
  /// This will cause the service to retrieve the [AuthCredentials] when trying
  /// to execute this endpoint
  const Endpoint._({
    required Uri endpoint,
    required ApiConverter<ResponseModel, RequestModel> converter,
    required HttpApiService apiService,
    Map<String, String> defaultHeaders = const {},
    bool authenticated = false,
  })  : _defaultHeaders = defaultHeaders,
        _converter = converter,
        _authenticated = authenticated,
        _apiService = apiService,
        _endpoint = endpoint;

  final Uri _endpoint;
  final HttpApiService _apiService;
  final bool _authenticated;
  final Map<String, String> _defaultHeaders;
  final ApiConverter<ResponseModel, RequestModel> _converter;

  /// get the currently set path.
  String get path => _endpoint.path;

  /// Executes a multipart POST request for file uploading.
  /// This method is used to upload files to the server.
  Future<ApiResponse<ResponseModel>> upload({
    required String fieldName,
    required List<int> fileBytes,
    required String fileName,
    RequestMethod method = RequestMethod.post,
    Map<String, String>? fields,
    Map<String, String>? headers,
  }) async {
    var response = await _apiService._upload(
      endpoint: _endpoint,
      fieldName: fieldName,
      fileBytes: fileBytes,
      fileName: fileName,
      method: method,
      fields: fields,
      headers: {..._defaultHeaders, ...?headers},
      isAuthenticated: _authenticated,
    );

    if (response.statusCode >= 400) {
      throw ApiException(inner: response);
    }

    try {
      var converted = _converter.toRepresentation(response.body);
      return ApiResponse(inner: response, result: converted);
    } on Exception catch (e, s) {
      throw ApiException(inner: response, error: e, stackTrace: s);
    }
  }

  /// Created a new endpoint from this endpoint.
  Endpoint<ResponseModel, RequestModel> child(String path) {
    var newPath = "${_endpoint.path}$path";
    return Endpoint._(
      endpoint: _endpoint.replace(path: newPath),
      converter: _converter,
      apiService: _apiService,
      authenticated: _authenticated,
      defaultHeaders: _defaultHeaders,
    );
  }

  /// Add to the existing default headers.
  ///
  /// This does overwrite existing headers of the same name.
  Endpoint<ResponseModel, RequestModel> addHeaders(
    Map<String, String> headers,
  ) =>
      setDefaultHeaders({
        ..._defaultHeaders,
        ...headers,
      });

  /// Set the default headers
  Endpoint<ResponseModel, RequestModel> setDefaultHeaders(
    Map<String, String> headers,
  ) =>
      Endpoint._(
        endpoint: _endpoint,
        converter: _converter,
        apiService: _apiService,
        authenticated: _authenticated,
        defaultHeaders: headers,
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
    var newPath = variables.entries.fold(
      _endpoint.path,
      (previousValue, element) =>
          previousValue.replaceAll(":${element.key}", "${element.value}"),
    );
    return Endpoint._(
      endpoint: _endpoint.replace(path: newPath),
      converter: _converter,
      apiService: _apiService,
      authenticated: _authenticated,
      defaultHeaders: _defaultHeaders,
    );
  }

  /// Marks that this method requires authentication to execute.
  Endpoint<ResponseModel, RequestModel> authenticate() => Endpoint._(
        endpoint: _endpoint,
        apiService: _apiService,
        converter: _converter,
        authenticated: true,
        defaultHeaders: _defaultHeaders,
      );

  /// Add a response converter to more easily handle response conversion
  Endpoint<Response, Request> withConverter<Response, Request>(
    ApiConverter<Response, Request> converter,
  ) =>
      Endpoint._(
        endpoint: _endpoint,
        converter: converter,
        apiService: _apiService,
        authenticated: _authenticated,
        defaultHeaders: _defaultHeaders,
      );

  /// Change the multiplicity of the endpoint
  Endpoint<Response, Request> changeMultiplicity<Response, Request>(
    ApiConverter<Response, Request> Function(
      MultiplicitySupportedConverter<ResponseModel, RequestModel> converter,
    ) changer,
  ) =>
      withConverter(
        changer(
          _converter
              as MultiplicitySupportedConverter<ResponseModel, RequestModel>,
        ),
      );

  /// Execute a GET request.
  Future<ApiResponse<ResponseModel>> get({
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/ >? queryParameters,
    Encoding? encoding,
  }) async =>
      _request(
        requestMethod: RequestMethod.get,
        headers: headers,
        queryParameters: queryParameters,
        encoding: encoding,
      );

  /// Execute a DELETE request.
  Future<ApiResponse<ResponseModel>> delete({
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/ >? queryParameters,
    RequestModel? requestModel,
    Encoding? encoding,
  }) async =>
      _request(
        requestMethod: RequestMethod.delete,
        headers: headers,
        queryParameters: queryParameters,
        requestModel: requestModel,
        encoding: encoding,
      );

  /// Execute a PATCH request.
  Future<ApiResponse<ResponseModel>> patch({
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/ >? queryParameters,
    RequestModel? requestModel,
    Encoding? encoding,
  }) async =>
      _request(
        requestMethod: RequestMethod.patch,
        headers: headers,
        queryParameters: queryParameters,
        requestModel: requestModel,
        encoding: encoding,
      );

  /// Execute a POST request.
  Future<ApiResponse<ResponseModel>> post({
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/ >? queryParameters,
    RequestModel? requestModel,
    Encoding? encoding,
  }) async =>
      _request(
        requestMethod: RequestMethod.post,
        headers: headers,
        queryParameters: queryParameters,
        requestModel: requestModel,
        encoding: encoding,
      );

  /// Execute a PUT request.
  Future<ApiResponse<ResponseModel>> put({
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/ >? queryParameters,
    RequestModel? requestModel,
    Encoding? encoding,
  }) async =>
      _request(
        requestMethod: RequestMethod.put,
        headers: headers,
        requestModel: requestModel,
        queryParameters: queryParameters,
        encoding: encoding,
      );

  Future<ApiResponse<ResponseModel>> _request({
    required RequestMethod requestMethod,
    Map<String, String>? headers,
    Map<String, dynamic /*String?|Iterable<String>*/ >? queryParameters,
    RequestModel? requestModel,
    Encoding? encoding,
  }) async {
    var endpoint = _endpoint.replace(queryParameters: queryParameters ?? {});

    Object? body;
    if (requestModel != null) {
      body = _converter.fromRepresentation(requestModel);
    }

    var response = await _apiService._request(
      endpoint,
      requestMethod,
      headers: {
        ..._defaultHeaders,
        ...?headers,
      },
      body: body,
      encoding: encoding,
      isAuthenticated: _authenticated,
    );

    if (response.statusCode >= 400) {
      throw ApiException(inner: response);
    }

    try {
      var converted = _converter.toRepresentation(response.body);

      return ApiResponse(inner: response, result: converted);

      // we catch any exception here because an converter might introduce
      // an exception, but we still would like access to the original response
      // for easier debugging
    } on Exception catch (e, s) {
      throw ApiException(
        inner: response,
        error: e,
        stackTrace: s,
      );
    }
  }
}

/// Exception that's thrown when the Api call resulted in an exception
class ApiException implements Exception {
  /// Creates an API Exception
  const ApiException({
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
  String toString() => "ApiException: ${inner.request?.url} -> $statusCode. "
      "\ndetails: $error\n$stackTrace";
}

/// A response representation of the API call.
class ApiResponse<Model> {
  /// Create an API response
  @visibleForTesting
  const ApiResponse({
    required this.inner,
    this.result,
  });

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
