import "dart:convert";

import "package:dart_api_service/src/api_service.dart";
import "package:fpdart/fpdart.dart";

/// Result of converting a response body into a representation.
typedef ToRepresentationResult<T> = Either<RequestObjectSerializationApiException, T>;

/// Result of converting a representation into a request body.
typedef FromRepresentationResult = Either<ResponseObjectSerializationApiException, Object>;

/// Interface defining the behaviour of a converter.
///
///
abstract interface class ApiConverter<Result, RequestObject> {
  /// Convert the response object to a [Result]
  ToRepresentationResult<Result> toRepresentation(Object object);

  /// convert the [Result] to a readable
  FromRepresentationResult fromRepresentation(RequestObject representation);

  /// Creates a modelJsonResponseConverter for a model
  static ModelJsonResponseConverter<T, T> model<T>({
    T Function(Map<String, dynamic>)? deserialize,
    Map<String, dynamic> Function(T)? serialize,
  }) => ModelJsonResponseConverter(
    deserialize: deserialize ?? (_) => throw UnimplementedError(),
    serialize: serialize ?? (_) => throw UnimplementedError(),
  );

  /// Creates a modelJsonResponseConverter for a model
  /// implementing [ApiSerializable]
  static ModelJsonResponseConverter<T, T> fromSerializable<T extends ApiSerializable>(
    T Function(Map<String, dynamic>) deserialize,
  ) => ModelJsonResponseConverter<T, T>(
    deserialize: deserialize,
    serialize: (t) => t.toMap(),
  );
}

/// Serializable object for quick converter creation
/// ignore: one_member_abstracts
abstract interface class ApiSerializable {
  /// conversion to a map object
  JsonObject toMap();
}

/// Interface to identify a converter as supporting multiplicity.
abstract interface class MultiplicitySupportedConverter<Response, Request> {
  /// Get a relevant converter supporting Lists
  ApiConverter<List<Response>, List<Request>> list();

  /// Get a relevant converter supporting Single object retrieval
  ApiConverter<Response, Request> single();
}

/// Basic converter for consistency. Not for external use.
class NonConverter<T> implements ApiConverter<T, T> {
  /// Creates a non working converter.
  const NonConverter();

  @override
  FromRepresentationResult fromRepresentation(T representation) => _fromRepresentation(() => representation as Object);

  @override
  ToRepresentationResult<T> toRepresentation(Object object) => _toRepresentation(() => object as T);
}

ToRepresentationResult<T> _toRepresentation<T>(T Function() convert) => Either.tryCatch(
  convert,
  (error, stackTrace) => RequestObjectSerializationApiException(
    error: error,
    stackTrace: stackTrace,
  ),
);

Either<ResponseObjectSerializationApiException, T> _fromRepresentation<T extends Object>(T Function() convert) =>
    Either.tryCatch(
      convert,
      (error, stackTrace) => ResponseObjectSerializationApiException(
        error: error,
        stackTrace: stackTrace,
      ),
    );

/// definition of a standard json object representation in dart
typedef JsonObject = Map<String, dynamic>;

/// Translates String to a `Map<String, dynamic>`
class MapJsonResponseConverter
    implements ApiConverter<JsonObject, JsonObject>, MultiplicitySupportedConverter<JsonObject, JsonObject> {
  /// Creates a MapJsonResponseConverter.
  const MapJsonResponseConverter();

  @override
  ToRepresentationResult<JsonObject> toRepresentation(Object object) => _toRepresentation(() {
    if (object is! String || object.isEmpty) {
      throw FormatException("Expected a non-empty JSON string", object);
    }
    return jsonDecode(object) as JsonObject;
  });

  @override
  FromRepresentationResult fromRepresentation(
    Map<String, dynamic> representation,
  ) => _fromRepresentation(() => jsonEncode(representation));

  @override
  ApiConverter<List<JsonObject>, List<JsonObject>> list() => const ListMapJsonResponseConverter();

  @override
  ApiConverter<JsonObject, JsonObject> single() => this;
}

/// Definition of a common json structure of a list of objects
typedef ListMapJsonResponse = List<JsonObject>;

/// Converter for a list of json objects
class ListMapJsonResponseConverter
    implements
        ApiConverter<ListMapJsonResponse, ListMapJsonResponse>,
        MultiplicitySupportedConverter<JsonObject, JsonObject> {
  /// Creates a ListMapJsonResponseConverter.
  const ListMapJsonResponseConverter();

  @override
  FromRepresentationResult fromRepresentation(
    ListMapJsonResponse representation,
  ) => _fromRepresentation(() => jsonEncode(representation));

  @override
  ToRepresentationResult<ListMapJsonResponse> toRepresentation(Object object) => _toRepresentation(() {
    final result = jsonDecode(object as String);
    if (result is! List) {
      throw FormatException("Expected a JSON list", object);
    }
    return [
      for (final entry in result)
        if (entry is Map<String, dynamic>) entry else throw FormatException("Expected a JSON object in list", entry),
    ];
  });

  @override
  ApiConverter<List<JsonObject>, List<JsonObject>> list() => this;

  @override
  ApiConverter<JsonObject, JsonObject> single() => const MapJsonResponseConverter();
}

/// A simple converter that parses a JSON string into a Map.
/// This is ideal for handling simple JSON object responses.
class JsonMapResponseConverter implements ApiConverter<Map<String, dynamic>, void> {
  /// Creates an instance of [JsonMapResponseConverter].
  const JsonMapResponseConverter();

  @override
  ToRepresentationResult<Map<String, dynamic>> toRepresentation(
    Object? input,
  ) => _toRepresentation(() {
    if (input is! String || input.isEmpty) {
      throw FormatException("Expected a non-empty JSON string", input);
    }
    return jsonDecode(input) as Map<String, dynamic>;
  });

  @override
  FromRepresentationResult fromRepresentation(void representation) =>
      _fromRepresentation(() => throw UnimplementedError());
}

/// A serializer made to support custom models to and from json mappings.
class ModelJsonResponseConverter<ResponseModel, RequestModel>
    implements ApiConverter<ResponseModel, RequestModel>, MultiplicitySupportedConverter<ResponseModel, RequestModel> {
  /// Creates a json serializer.
  ModelJsonResponseConverter({
    required this._deserialize,
    required this._serialize,
  });

  final MapJsonResponseConverter _jsonConverter = const MapJsonResponseConverter();
  final ResponseModel Function(Map<String, dynamic>) _deserialize;
  final Map<String, dynamic> Function(RequestModel) _serialize;

  @override
  FromRepresentationResult fromRepresentation(RequestModel representation) =>
      _fromRepresentation(() => _serialize(representation)).flatMap(_jsonConverter.fromRepresentation);

  @override
  ToRepresentationResult<ResponseModel> toRepresentation(Object object) =>
      _jsonConverter.toRepresentation(object).flatMap((map) => _toRepresentation(() => _deserialize(map)));

  @override
  ApiConverter<List<ResponseModel>, List<RequestModel>> list() => ModelListJsonResponseConverter(
    deserialize: _deserialize,
    serialize: _serialize,
  );

  @override
  ApiConverter<ResponseModel, RequestModel> single() => this;
}

/// A serializer made to support custom models to and from json mappings.
class ModelListJsonResponseConverter<ResponseModel, RequestModel>
    implements
        ApiConverter<List<ResponseModel>, List<RequestModel>>,
        MultiplicitySupportedConverter<ResponseModel, RequestModel> {
  /// Creates a json serializer.
  ModelListJsonResponseConverter({
    required this._deserialize,
    required this._serialize,
  });

  final ListMapJsonResponseConverter _jsonConverter = const ListMapJsonResponseConverter();
  final ResponseModel Function(Map<String, dynamic>) _deserialize;
  final Map<String, dynamic> Function(RequestModel) _serialize;

  @override
  FromRepresentationResult fromRepresentation(
    List<RequestModel> representation,
  ) => _fromRepresentation(
    () => [for (final entry in representation) _serialize(entry)],
  ).flatMap(_jsonConverter.fromRepresentation);

  @override
  ToRepresentationResult<List<ResponseModel>> toRepresentation(Object object) => _jsonConverter
      .toRepresentation(object)
      .flatMap(
        (maps) => _toRepresentation(() => maps.map(_deserialize).toList()),
      );

  @override
  ApiConverter<List<ResponseModel>, List<RequestModel>> list() => this;

  @override
  ApiConverter<ResponseModel, RequestModel> single() => ModelJsonResponseConverter(
    deserialize: _deserialize,
    serialize: _serialize,
  );
}

/// A converter that only supports serialization,
/// ideal for write only endpoints
class WriteOnlyJsonMapResponseConverter implements ApiConverter<void, Map<String, dynamic>> {
  /// Creates a WriteOnlyJsonMapResponseConverter.
  const WriteOnlyJsonMapResponseConverter();

  @override
  FromRepresentationResult fromRepresentation(
    Map<String, dynamic> representation,
  ) => _fromRepresentation(() => jsonEncode(representation));

  @override
  ToRepresentationResult<void> toRepresentation(_) => Either.of(null);
}

/// A converter that only supports deserialization,
/// ideal for read only endpoints
class ReadOnlyJsonMapResponseConverter implements ApiConverter<Map<String, dynamic>, void> {
  /// Creates a ReadOnlyJsonMapResponseConverter.
  const ReadOnlyJsonMapResponseConverter();

  @override
  FromRepresentationResult fromRepresentation(_) => Either.of("");

  @override
  ToRepresentationResult<Map<String, dynamic>> toRepresentation(
    Object object,
  ) => _toRepresentation(
    () => jsonDecode(object as String) as Map<String, dynamic>,
  );
}

/// A converter that only supports serialization,
/// ideal for write only endpoints
class WriteOnlyModelJsonResponseConverter<RequestModel> implements ApiConverter<void, RequestModel> {
  /// Creates a write only json serializer.
  WriteOnlyModelJsonResponseConverter({required this._serialize});

  final Map<String, dynamic> Function(RequestModel) _serialize;

  @override
  FromRepresentationResult fromRepresentation(RequestModel representation) =>
      _fromRepresentation(() => jsonEncode(_serialize(representation)));

  @override
  ToRepresentationResult<void> toRepresentation(_) => Either.of(null);
}

/// A converter that only supports deserialization,
/// ideal for read only endpoints
class ReadOnlyModelJsonResponseConverter<ResponseModel> implements ApiConverter<ResponseModel, void> {
  /// Creates a read only json serializer.
  ReadOnlyModelJsonResponseConverter({required this._deserialize});

  final ResponseModel Function(Map<String, dynamic>) _deserialize;

  @override
  FromRepresentationResult fromRepresentation(_) => Either.of("");

  @override
  ToRepresentationResult<ResponseModel> toRepresentation(Object object) =>
      _toRepresentation(() => _deserialize(jsonDecode(object as String)));
}
