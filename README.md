
A simple API service that follows a FirebaseFirestore-like definition of resource endpoints.

## Features

- Call endpoints with Put, Patch, Delete, Post and Get http methods
- Use converters for type safe interaction with endpoints.
- Allow authentication due to an auth credentials service.
- Errors are returned as values (fpdart `TaskEither`/`Either`) instead of thrown.
- Mock endpoints in tests, or fake responses at runtime, without a mocking library.

## Getting started

To use the this API service in your Dart or Flutter, add the following to the pubspec.yaml

```yaml
  dart_api_service:
    hosted: https://forgejo.internal.iconica.nl/api/packages/internal/pub/
    version: <Version>
```

## Usage

TODO: Include short and useful examples for package users. Add longer examples
to `/example` folder. 

```dart
  var authService = MockAuthService();
  var apiService = HttpApiService(
    baseUrl: Uri.parse("https://jsonplaceholder.typicode.com"),
    authenticationService: authService,
  );

  var converter = ApiConverter.fromSerializable(PostComment.fromMap);

  var endPoint = apiService.endpoint("/posts/:post");
  var comments = endPoint
      .child("/comments")
      .withConverter(
        converter.list(),
      )
      .authenticate()
      .addHeaders({
    "accept": "application/json",
  }).withVariables({
    "post": 1,
  });

  // Requests return a TaskEither; nothing runs until `.run()` is called.
  final result = await comments.get().run();
  switch (result) {
    case Right(value: final post):
      print(post.result);
    case Left(value: final ApiResponseException e):
      print(e.statusCode);
      print(e.inner.body);
    case Left(value: final e):
      print(e);
  }
```

## Error handling

Requests return `TaskEither<ApiException, ApiResponse<T>>`. Converters return
`Either` with a `RequestObjectSerializationApiException` (from
`toRepresentation`) or a `ResponseObjectSerializationApiException` (from
`fromRepresentation`).

By default a status code of 400 or above results in an `ApiResponseException`.
Set `allResponsesAllowed` on the `HttpApiService`, or call
`endpoint.withAllResponsesAllowed()`, to bypass this check. You are then
responsible for handling error responses and differing body structures in your
converters.

## Mocking

`HttpApiService.mocked` creates a service backed by a `MockHttpClient`. It does
not use a mocking library, so it also works in release builds (for example for
demo modes). Mocks are defined with the same syntax as regular calls, using
`getMocker()`, `postMocker()`, `putMocker()`, `patchMocker()` or
`deleteMocker()` on an endpoint.

```dart
final service = HttpApiService<Object>.mocked(
  baseUrl: Uri.parse("https://test.com"),
  mocks: [
    (service) => service
        .endpoint("/test/:id")
        .withVariables({"id": "1"})
        .getMocker()
        .returns(
          (request) => jsonEncode({"something": request.queryParameters["test"]}),
        ),
  ],
);
```

- Variables (`:id`) that are not bound with `withVariables` match any value.
- Use `respondsWith` instead of `returns` to control the status code and headers.
- Requests that match no mock go to the optional `fallbackClient`. Without one
  they fail with an `ApiConnectionFailureException` explaining why no mock
  could be resolved.

## Issues

Please file any issues, bugs or feature request as an issue on our [GitHub](https://github.com/Iconica-Development/dart_api_service) page. Commercial support is available if you need help with integration with your app or services. You can contact us at [support@iconica.nl](mailto:support@iconica.nl).

## Want to contribute

If you would like to contribute to the plugin (e.g. by improving the documentation, solving a bug or adding a cool new feature), please carefully review our [contribution guide](./CONTRIBUTING.md) and send us your [pull request](https://github.com/Iconica-Development/dart_api_service/pulls).

## Author

This dart_api_service for Flutter and Dart is developed by [Iconica](https://iconica.nl). You can contact us at <support@iconica.nl>