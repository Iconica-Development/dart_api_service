import "dart:convert";

import "package:dart_api_service/dart_api_service.dart";
import "package:mocktail/mocktail.dart";
import "package:test/test.dart";

class MockedClient extends Mock implements Client {}

void main() {
  group("ApiService", () {
    final baseUrl = Uri.parse("https://test.com");
    final client = MockedClient();
    late HttpApiService sut;

    registerFallbackValue(Uri());

    setUp(() {
      sut = HttpApiService(baseUrl: baseUrl, client: client);
    });

    group("Should use proper headers when given through", () {
      const testHeaders = {"test": "value"};

      // ignore: discarded_futures
      Future<Response> getDefinition() => client.post(
        any<Uri>(),
        headers: any(named: "headers", that: equals(testHeaders)),
      );

      setUp(() {
        when(getDefinition).thenAnswer((invocation) async => Response("", 200));
      });

      test("request call", () async {
        await sut.endpoint("/").post(headers: testHeaders).run();

        verify(getDefinition).called(1);
      });

      test("endpoint headers", () async {
        await sut.endpoint("/").addHeaders(testHeaders).post().run();

        verify(getDefinition).called(1);
      });

      test("default headers", () async {
        sut = HttpApiService(
          baseUrl: baseUrl,
          client: client,
          defaultHeaders: testHeaders,
        );

        await sut.endpoint("/").post().run();

        verify(getDefinition).called(1);
      });

      // testcase checking a bug that caused headers to be lost as soon as
      // an endpoint converter was used.
      test("default headers with a converter", () async {
        sut = HttpApiService(
          baseUrl: baseUrl,
          client: client,
          defaultHeaders: testHeaders,
        );

        await sut.endpoint("/").withConverter(const NonConverter()).post().run();

        verify(getDefinition).called(1);
      });
    });

    group("Should use correct httpMethod when calling", () {
      test("post", () async {
        final expected = Response("test", 200);

        Future<Response> postDefinition() => client.post(
          any<Uri>(),
          headers: any(named: "headers"),
          body: any(named: "body"),
          encoding: any(named: "encoding"),
        );

        when(postDefinition).thenAnswer((invocation) async => expected);

        final response = await sut.endpoint("/").post().run();

        expect(response.toNullable()?.inner, equals(expected));

        verify(postDefinition).called(1);
      });

      test("get", () async {
        final expected = Response("test", 200);

        Future<Response> getDefinition() => client.get(any<Uri>(), headers: any(named: "headers"));

        when(getDefinition).thenAnswer((invocation) async => expected);

        final response = await sut.endpoint("/").get().run();

        expect(response.toNullable()?.inner, equals(expected));

        verify(getDefinition).called(1);
      });

      test("delete", () async {
        final expected = Response("test", 200);

        Future<Response> deleteDefinition() => client.delete(
          any<Uri>(),
          headers: any(named: "headers"),
          body: any(named: "body"),
          encoding: any(named: "encoding"),
        );

        when(deleteDefinition).thenAnswer((invocation) async => expected);

        final response = await sut.endpoint("/").delete().run();

        expect(response.toNullable()?.inner, equals(expected));

        verify(deleteDefinition).called(1);
      });

      test("patch", () async {
        final expected = Response("test", 200);

        Future<Response> patchDefinition() => client.patch(
          any<Uri>(),
          headers: any(named: "headers"),
          body: any(named: "body"),
          encoding: any(named: "encoding"),
        );

        when(patchDefinition).thenAnswer((invocation) async => expected);

        final response = await sut.endpoint("/").patch().run();

        expect(response.toNullable()?.inner, equals(expected));

        verify(patchDefinition).called(1);
      });

      test("put", () async {
        final expected = Response("test", 200);

        Future<Response> putDefinition() => client.put(
          any<Uri>(),
          headers: any(named: "headers"),
          body: any(named: "body"),
          encoding: any(named: "encoding"),
        );

        when(putDefinition).thenAnswer((invocation) async => expected);

        final response = await sut.endpoint("/").put().run();

        expect(response.toNullable()?.inner, equals(expected));

        verify(putDefinition).called(1);
      });
    });
  });

  group("HttpApiService.mocked", () {
    final baseUrl = Uri.parse("https://test.com");

    test("answers a matching request", () async {
      final service = HttpApiService<Object>.mocked(
        baseUrl: baseUrl,
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

      final result = await service
          .endpoint("/test/1")
          .withConverter(const MapJsonResponseConverter())
          .get(queryParameters: {"test": "value"})
          .run();

      expect(result.toNullable()?.result, {"something": "value"});
    });

    test("unbound variables match any value and method must match", () async {
      final service = HttpApiService<Object>.mocked(
        baseUrl: baseUrl,
        mocks: [
          (service) => service.endpoint("/test/:id").postMocker().returns((_) => "", statusCode: 201),
        ],
      );

      final created = await service.endpoint("/test/5").post().run();
      expect(created.toNullable()?.statusCode, 201);

      final wrongMethod = await service.endpoint("/test/5").get().run();
      expect(
        wrongMethod.getLeft().toNullable(),
        isA<ApiConnectionFailureException>(),
      );
    });

    test("unresolved request reports the reason", () async {
      final service = HttpApiService<Object>.mocked(
        baseUrl: baseUrl,
        mocks: [],
      );

      final result = await service.endpoint("/missing").get().run();
      final error = result.getLeft().toNullable();

      expect(error, isA<ApiConnectionFailureException>());
      expect(
        (error! as ApiConnectionFailureException).reason,
        contains("No mock resolved GET"),
      );
    });

    test("delegates unmatched requests to the fallback client", () async {
      registerFallbackValue(Request("GET", Uri()));
      final fallback = MockedClient();
      when(() => fallback.send(any())).thenAnswer((_) async => StreamedResponse(Stream.value([]), 202));

      final service = HttpApiService<Object>.mocked(
        baseUrl: baseUrl,
        mocks: [],
        fallbackClient: fallback,
      );

      final result = await service.endpoint("/other").get().run();
      expect(result.toNullable()?.statusCode, 202);
    });
  });
}
