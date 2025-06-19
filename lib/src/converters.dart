import "dart:convert";

/// Interface defining the behaviour of a converter.
///
///
abstract interface class ApiConverter<Result, RequestObject> {
  /// Convert the response object to a [Result]
  Result toRepresentation(Object object);

  /// convert the [Result] to a readable
  Object fromRepresentation(RequestObject representation);

  /// Creates a modelJsonResponseConverter for a model
  static ModelJsonResponseConverter<T, T> model<T>({
    T Function(Map<String, dynamic>)? deserialize,
    Map<String, dynamic> Function(T)? serialize,
  }) =>
      ModelJsonResponseConverter(
        deserialize: deserialize ?? (_) => throw UnimplementedError(),
        serialize: serialize ?? (_) => throw UnimplementedError(),
      );

  /// Creates a modelJsonResponseConverter for a model
  /// implementing [ApiSerializable]
  static ModelJsonResponseConverter<T, T>
      fromSerializable<T extends ApiSerializable>(
    T Function(Map<String, dynamic>) deserialize,
  ) =>
          ModelJsonResponseConverter<T, T>(
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
  Object fromRepresentation(T representation) => representation as Object;

  @override
  T toRepresentation(Object object) => object as T;
}

/// definition of a standard json object representation in dart
typedef JsonObject = Map<String, dynamic>;

/// Translates String to a Map<String, dynamic>
class MapJsonResponseConverter
    implements
        ApiConverter<JsonObject, JsonObject>,
        MultiplicitySupportedConverter<JsonObject, JsonObject> {
  /// Creates a MapJsonResponseConverter.
  const MapJsonResponseConverter();

  @override
  Map<String, dynamic> toRepresentation(Object object) {
    if (object is! String || object.isEmpty) return {};
    return jsonDecode(object);
  }

  @override
  Object fromRepresentation(Map<String, dynamic> representation) =>
      jsonEncode(representation);

  @override
  ApiConverter<List<JsonObject>, List<JsonObject>> list() =>
      const ListMapJsonResponseConverter();

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
  Object fromRepresentation(ListMapJsonResponse representation) =>
      jsonEncode(representation);

  @override
  ListMapJsonResponse toRepresentation(Object object) {
    var result = jsonDecode(object as String);
    if (result is List) {
      return [
        for (var entry in result)
          if (entry is Map<String, dynamic>) entry,
      ];
    }
    return [];
  }

  @override
  ApiConverter<List<JsonObject>, List<JsonObject>> list() => this;

  @override
  ApiConverter<JsonObject, JsonObject> single() =>
      const MapJsonResponseConverter();
}

/// A serializer made to support custom models to and from json mappings.
class ModelJsonResponseConverter<ResponseModel, RequestModel>
    implements
        ApiConverter<ResponseModel, RequestModel>,
        MultiplicitySupportedConverter<ResponseModel, RequestModel> {
  /// Creates a json serializer.
  ModelJsonResponseConverter({
    required ResponseModel Function(Map<String, dynamic>) deserialize,
    required Map<String, dynamic> Function(RequestModel) serialize,
  })  : _serialize = serialize,
        _deserialize = deserialize;

  final MapJsonResponseConverter _jsonConverter =
      const MapJsonResponseConverter();
  final ResponseModel Function(Map<String, dynamic>) _deserialize;
  final Map<String, dynamic> Function(RequestModel) _serialize;

  @override
  Object fromRepresentation(RequestModel representation) =>
      _jsonConverter.fromRepresentation(_serialize(representation));

  @override
  ResponseModel toRepresentation(Object object) =>
      _deserialize(_jsonConverter.toRepresentation(object));

  @override
  ApiConverter<List<ResponseModel>, List<RequestModel>> list() =>
      ModelListJsonResponseConverter(
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
    required ResponseModel Function(Map<String, dynamic>) deserialize,
    required Map<String, dynamic> Function(RequestModel) serialize,
  })  : _serialize = serialize,
        _deserialize = deserialize;

  final ListMapJsonResponseConverter _jsonConverter =
      const ListMapJsonResponseConverter();
  final ResponseModel Function(Map<String, dynamic>) _deserialize;
  final Map<String, dynamic> Function(RequestModel) _serialize;

  @override
  Object fromRepresentation(List<RequestModel> representation) =>
      _jsonConverter.fromRepresentation([
        for (var entry in representation) ...[
          _serialize(entry),
        ],
      ]);

  @override
  List<ResponseModel> toRepresentation(Object object) =>
      _jsonConverter.toRepresentation(object).map(_deserialize).toList();

  @override
  ApiConverter<List<ResponseModel>, List<RequestModel>> list() => this;

  @override
  ApiConverter<ResponseModel, RequestModel> single() =>
      ModelJsonResponseConverter(
        deserialize: _deserialize,
        serialize: _serialize,
      );
}
