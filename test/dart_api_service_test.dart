import "package:dart_api_service/dart_api_service.dart";
import "package:http/http.dart";
import "package:mocktail/mocktail.dart";
import "package:test/test.dart";

class MockedClient extends Mock implements Client {}

void main() {
  group("ApiService", () {
    var baseUrl = Uri.parse("https://test.com");
    var client = MockedClient();
    late HttpApiService sut;

    registerFallbackValue(Uri());

    setUp(() {
      sut = HttpApiService(baseUrl: baseUrl, client: client);
    });

    group("Should use correct httpMethod when calling", () {
      test(
        "post",
        () async {
          var expected = Response("test", 200);

          Future<Response> postDefinition() => client.post(
                any<Uri>(),
                headers: any(named: "headers"),
                body: any(named: "body"),
                encoding: any(named: "encoding"),
              );

          when(
            postDefinition,
          ).thenAnswer((invocation) async => expected);

          var response = await sut.endpoint("/").post();

          expect(response.inner, equals(expected));

          verify(postDefinition).called(1);
        },
      );

      test(
        "get",
        () async {
          var expected = Response("test", 200);

          Future<Response> getDefinition() => client.get(
                any<Uri>(),
                headers: any(named: "headers"),
              );

          when(
            getDefinition,
          ).thenAnswer((invocation) async => expected);

          var response = await sut.endpoint("/").get();

          expect(response.inner, equals(expected));

          verify(getDefinition).called(1);
        },
      );

      test(
        "delete",
        () async {
          var expected = Response("test", 200);

          Future<Response> deleteDefinition() => client.delete(
                any<Uri>(),
                headers: any(named: "headers"),
                body: any(named: "body"),
                encoding: any(named: "encoding"),
              );

          when(
            deleteDefinition,
          ).thenAnswer((invocation) async => expected);

          var response = await sut.endpoint("/").delete();

          expect(response.inner, equals(expected));

          verify(deleteDefinition).called(1);
        },
      );

      test(
        "patch",
        () async {
          var expected = Response("test", 200);

          Future<Response> patchDefinition() => client.patch(
                any<Uri>(),
                headers: any(named: "headers"),
                body: any(named: "body"),
                encoding: any(named: "encoding"),
              );

          when(
            patchDefinition,
          ).thenAnswer((invocation) async => expected);

          var response = await sut.endpoint("/").patch();

          expect(response.inner, equals(expected));

          verify(patchDefinition).called(1);
        },
      );

      test(
        "put",
        () async {
          var expected = Response("test", 200);

          Future<Response> putDefinition() => client.put(
                any<Uri>(),
                headers: any(named: "headers"),
                body: any(named: "body"),
                encoding: any(named: "encoding"),
              );

          when(
            putDefinition,
          ).thenAnswer((invocation) async => expected);

          var response = await sut.endpoint("/").put();

          expect(response.inner, equals(expected));

          verify(putDefinition).called(1);
        },
      );
    });
  });
}
