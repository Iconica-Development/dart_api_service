## 1.2.1
- Added field and request method option for the multipart file upload

## 1.2.0
- Added support for multipart file uploads.

## 1.1.3
- Allow access to the baseUrl, client and authenticationService properties.

## 1.1.2
- Added export for `package:http/http.dart` so Client can be imported directly by users of this package.

## 1.1.1
- Change meta package to any instead of specific version.

## 1.1.0
- Added option to provide a list as query parameter.

## 1.0.4
- Fix headers not being copied with changing the converter for an endpoint
- Update formatting
- Add support for empty bodies in jsonresponse converter

## 1.0.3
- Fix query parameters never being provided to the actual request

## 1.0.2
- Fix token auth to fit the bearer standard
- Fix JWT auth by removing the `:` in the header

## 1.0.1
- Fix api service calls not using _authenticated value
- Add meaningful toString for ApiException

## 1.0.0

- Initial version of the API service
- Supports basic http methods
- Supports authentication integration
- Api method in a builder style
- Supports json model serialization

