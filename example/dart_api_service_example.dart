// ignore_for_file: avoid_print

import "dart:async";
import "dart:io";

import "package:dart_api_service/dart_api_service.dart";

class MockAuthService extends AuthenticationService {
  @override
  FutureOr<AuthCredentials> getCredentials() => MockCredentials();
}

class MockCredentials implements AuthCredentials {
  @override
  Map<String, String> get headers {
    print("using authenticated calls");
    return {};
  }
}

class PostComment implements ApiSerializable {
  PostComment({
    required this.postId,
    required this.id,
    required this.name,
    required this.email,
    required this.body,
  });

  factory PostComment.fromMap(Map<String, dynamic> map) => PostComment(
        postId: (map["postId"] ?? 0) as int,
        id: (map["id"] ?? 0) as int,
        name: (map["name"] ?? "") as String,
        email: (map["email"] ?? "") as String,
        body: (map["body"] ?? "") as String,
      );
  final int postId;
  final int id;
  final String name;
  final String email;
  final String body;

  PostComment copyWith({
    int? postId,
    int? id,
    String? name,
    String? email,
    String? body,
  }) =>
      PostComment(
        postId: postId ?? this.postId,
        id: id ?? this.id,
        name: name ?? this.name,
        email: email ?? this.email,
        body: body ?? this.body,
      );

  @override
  Map<String, dynamic> toMap() => <String, dynamic>{
        "postId": postId,
        "id": id,
        "name": name,
        "email": email,
        "body": body,
      };

  @override
  String toString() => "PostComment("
      "postId: $postId, "
      "id: $id, "
      "name: $name, "
      "email: $email, "
      "body: $body)";
}

void main() async {
  var authService = MockAuthService();
  var apiService = HttpApiService(
    defaultHeaders: {"Content-Type": "application/json"},
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
    print(post.inner.request?.headers);
  } on ApiException catch (e) {
    print(e.statusCode);
    print(e.inner.body);
  }

  exit(1);
}
