import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flashcard_app/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generateCards uses an extended receive timeout for AI calls', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      responseJson: '{"items":[]}',
    );
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: 'http://localhost/api/v1',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    )..httpClientAdapter = adapter;
    final ApiClient client = ApiClient(dio: dio);

    await client.generateCards(
      token: 'token',
      topic: 'Education Principles',
      context: 'Teaching principles guide learning design.',
      cardCount: 3,
      difficulty: 'standard',
    );

    expect(adapter.lastOptions?.path, '/ai/generate');
    expect(adapter.lastOptions?.receiveTimeout, const Duration(seconds: 90));
  });

  test('generateCardsFromFile uses an extended receive timeout', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      responseJson:
          '{"document":{"title":"education.md","mime_type":"text/markdown","text_preview":"preview","text_length":7},"items":[]}',
    );
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: 'http://localhost/api/v1',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    )..httpClientAdapter = adapter;
    final ApiClient client = ApiClient(dio: dio);

    await client.generateCardsFromFile(
      token: 'token',
      filename: 'education.md',
      bytes: 'content'.codeUnits,
      topic: 'Education Principles',
      cardCount: 3,
      difficulty: 'standard',
      cardTypes: const <String>['basic'],
    );

    expect(adapter.lastOptions?.path, '/ai/import-file');
    expect(adapter.lastOptions?.receiveTimeout, const Duration(seconds: 90));
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.responseJson});

  final String responseJson;
  RequestOptions? lastOptions;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    return ResponseBody.fromString(
      responseJson,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
