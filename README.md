
A simple API service that follows a FirebaseFirestore-like definition of resource endpoints.

## Features

- Call endpoints with Put, Patch, Delete, Post and Get http methods
- Use converters for type safe interaction with endpoints.
- Allow authentication due to an auth credentials service.

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

  try {
    var post = await comments.get();
    print(post.result);
  } on ApiException catch (e) {
    print(e.statusCode);
    print(e.inner.body);
  }
```

## Issues

Please file any issues, bugs or feature request as an issue on our [GitHub](https://github.com/Iconica-Development/dart_api_service) page. Commercial support is available if you need help with integration with your app or services. You can contact us at [support@iconica.nl](mailto:support@iconica.nl).

## Want to contribute

If you would like to contribute to the plugin (e.g. by improving the documentation, solving a bug or adding a cool new feature), please carefully review our [contribution guide](./CONTRIBUTING.md) and send us your [pull request](https://github.com/Iconica-Development/dart_api_service/pulls).

## Author

This dart_api_service for Flutter and Dart is developed by [Iconica](https://iconica.nl). You can contact us at <support@iconica.nl>