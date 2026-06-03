import 'dart:convert';

import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({Dio? dio}) : _dio = dio ?? _createDefaultDio();

  static const Duration aiReceiveTimeout = Duration(seconds: 90);

  static Dio _createDefaultDio() {
    return Dio(
      BaseOptions(
        baseUrl: const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://8.135.61.137:8080/api/v1',
        ),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: <String, String>{'Content-Type': 'application/json'},
      ),
    );
  }

  final Dio _dio;

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/auth/register',
      data: <String, dynamic>{
        'email': email,
        'password': password,
        'display_name': displayName,
      },
    );
    return _requireMap(response.data, '/auth/register');
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/auth/login',
      data: <String, dynamic>{'email': email, 'password': password},
    );
    return _requireMap(response.data, '/auth/login');
  }

  Future<List<Map<String, dynamic>>> listFolders(String token) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/folders',
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _toMapList(response.data, 'items');
  }

  Future<Map<String, dynamic>> createFolder({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/folders',
      data: payload,
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _requireMap(response.data, '/folders');
  }

  Future<Map<String, dynamic>> updateFolder({
    required String token,
    required String folderId,
    required Map<String, dynamic> payload,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/folders/$folderId',
      data: payload,
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _requireMap(response.data, '/folders/$folderId');
  }

  Future<void> deleteFolder({
    required String token,
    required String folderId,
  }) async {
    await _dio.delete<void>(
      '/folders/$folderId',
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
  }

  Future<List<Map<String, dynamic>>> listDecks(String token) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/decks',
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _toMapList(response.data, 'items');
  }

  Future<Map<String, dynamic>> createDeck({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/decks',
      data: payload,
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _requireMap(response.data, '/decks');
  }

  Future<Map<String, dynamic>> updateDeck({
    required String token,
    required String deckId,
    required Map<String, dynamic> payload,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/decks/$deckId',
      data: payload,
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _requireMap(response.data, '/decks/$deckId');
  }

  Future<void> deleteDeck({
    required String token,
    required String deckId,
  }) async {
    await _dio.delete<void>(
      '/decks/$deckId',
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
  }

  Future<List<Map<String, dynamic>>> listCards({
    required String token,
    required String deckId,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/decks/$deckId/cards',
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _toMapList(response.data, 'items');
  }

  Future<Map<String, dynamic>> createCard({
    required String token,
    required String deckId,
    required Map<String, dynamic> payload,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/decks/$deckId/cards',
      data: payload,
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _requireMap(response.data, '/decks/$deckId/cards');
  }

  Future<void> deleteCard({
    required String token,
    required String cardId,
  }) async {
    await _dio.delete<void>(
      '/cards/$cardId',
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
  }

  Future<Map<String, dynamic>> updateCard({
    required String token,
    required String cardId,
    required Map<String, dynamic> payload,
  }) async {
    final Response<dynamic> response = await _dio.put<dynamic>(
      '/cards/$cardId',
      data: payload,
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _requireMap(response.data, '/cards/$cardId');
  }

  Future<List<Map<String, dynamic>>> listDueCards({
    required String token,
    String? deckId,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/review/due',
      queryParameters: deckId == null
          ? null
          : <String, dynamic>{'deck_id': deckId},
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _toMapList(response.data, 'items');
  }

  Future<Map<String, dynamic>> submitReview({
    required String token,
    required String cardId,
    required int rating,
    required int durationMs,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/review/submit',
      data: <String, dynamic>{
        'card_id': cardId,
        'rating': rating,
        'duration_ms': durationMs,
      },
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _requireMap(response.data, '/review/submit');
  }

  Future<Map<String, dynamic>> syncPush({
    required String token,
    required List<Map<String, dynamic>> operations,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/sync/push',
      data: <String, dynamic>{'operations': operations},
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _requireMap(response.data, '/sync/push');
  }

  Future<Map<String, dynamic>> syncPull({required String token}) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/sync/pull',
      options: Options(
        headers: <String, String>{'Authorization': 'Bearer $token'},
      ),
    );
    return _requireMap(response.data, '/sync/pull');
  }

  Future<List<Map<String, dynamic>>> generateCards({
    required String token,
    required String topic,
    required String context,
    required int cardCount,
    required String difficulty,
    Map<String, dynamic>? policy,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'topic': topic,
      'context': context,
      'difficulty': difficulty,
    };
    if (cardCount > 0) {
      payload['card_count'] = cardCount;
    }
    if (policy != null) {
      payload['policy'] = policy;
    }
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/ai/generate',
      data: payload,
      options: _aiOptions(token),
    );
    return _toMapList(response.data, 'items');
  }

  Future<Map<String, dynamic>> generateCardsFromFile({
    required String token,
    required String filename,
    required List<int> bytes,
    required String topic,
    required int cardCount,
    required String difficulty,
    required List<String> cardTypes,
    Map<String, dynamic>? policy,
  }) async {
    final FormData formData = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'topic': topic,
      'difficulty': difficulty,
      'card_types': cardTypes.join(','),
      'strategy': 'fsrs_friendly',
      if (policy != null) 'policy_json': jsonEncode(policy),
    });
    if (cardCount > 0) {
      formData.fields.add(
        MapEntry<String, String>('card_count', cardCount.toString()),
      );
    }
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/ai/import-file',
      data: formData,
      options: _aiOptions(token),
    );
    return _requireMap(response.data, '/ai/import-file');
  }

  Future<Map<String, dynamic>> startAIGenerationJob({
    required String token,
    required String topic,
    required String context,
    required int cardCount,
    required String difficulty,
    Map<String, dynamic>? policy,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'topic': topic,
      'context': context,
      'difficulty': difficulty,
    };
    if (cardCount > 0) {
      payload['card_count'] = cardCount;
    }
    if (policy != null) {
      payload['policy'] = policy;
    }
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/ai/generate-jobs',
      data: payload,
      options: _aiOptions(token),
    );
    return _requireMap(response.data, '/ai/generate-jobs');
  }

  Future<Map<String, dynamic>> startAIGenerationJobFromFile({
    required String token,
    required String filename,
    required List<int> bytes,
    required String topic,
    required int cardCount,
    required String difficulty,
    required List<String> cardTypes,
    Map<String, dynamic>? policy,
  }) async {
    final FormData formData = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      'topic': topic,
      'difficulty': difficulty,
      'card_types': cardTypes.join(','),
      'strategy': 'fsrs_friendly',
      if (policy != null) 'policy_json': jsonEncode(policy),
    });
    if (cardCount > 0) {
      formData.fields.add(
        MapEntry<String, String>('card_count', cardCount.toString()),
      );
    }
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/ai/import-file-job',
      data: formData,
      options: _aiOptions(token),
    );
    return _requireMap(response.data, '/ai/import-file-job');
  }

  Future<List<Map<String, dynamic>>> listAIGenerationJobs({
    required String token,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/ai/generate-jobs',
      options: _aiOptions(token),
    );
    return _toMapList(response.data, 'items');
  }

  Future<Map<String, dynamic>> getAIGenerationJob({
    required String token,
    required String jobId,
  }) async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '/ai/generate-jobs/$jobId',
      options: _aiOptions(token),
    );
    return _requireMap(response.data, '/ai/generate-jobs/$jobId');
  }

  Future<List<Map<String, dynamic>>> rewriteCardWithAI({
    required String token,
    required String title,
    required String content,
    required String rewriteType,
    required String instruction,
    String? cardId,
  }) async {
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/ai/rewrite-card',
      data: <String, dynamic>{
        'card_id': cardId,
        'title': title,
        'content': content,
        'rewrite_type': rewriteType,
        'instruction': instruction,
      },
      options: _aiOptions(token),
    );
    return _toMapList(response.data, 'candidates');
  }

  Future<Map<String, dynamic>> chatWithAICards({
    required String token,
    required String topic,
    required String instruction,
    required int cardCount,
    required String difficulty,
    required List<Map<String, String>> messages,
    required List<Map<String, dynamic>> items,
    String? operation,
    List<int> selectedIndexes = const <int>[],
    Map<String, dynamic>? reference,
    Map<String, dynamic>? policy,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'topic': topic,
      'instruction': instruction,
      'difficulty': difficulty,
      'messages': messages,
      'items': items,
    };
    if (cardCount > 0) {
      payload['card_count'] = cardCount;
    }
    if (operation != null && operation.trim().isNotEmpty) {
      payload['operation'] = operation;
    }
    if (selectedIndexes.isNotEmpty) {
      payload['selected_indexes'] = selectedIndexes;
    }
    if (reference != null) {
      payload['reference'] = reference;
    }
    if (policy != null) {
      payload['policy'] = policy;
    }
    final Response<dynamic> response = await _dio.post<dynamic>(
      '/ai/chat-cards',
      data: payload,
      options: _aiOptions(token),
    );
    return _requireMap(response.data, '/ai/chat-cards');
  }

  Options _aiOptions(String token) {
    return Options(
      headers: <String, String>{'Authorization': 'Bearer $token'},
      receiveTimeout: aiReceiveTimeout,
    );
  }

  List<Map<String, dynamic>> _toMapList(dynamic data, String field) {
    final Map<String, dynamic> response = _requireMap(data, field);
    final dynamic rawItems = response[field];
    if (rawItems == null) {
      return <Map<String, dynamic>>[];
    }
    if (rawItems is! List) {
      throw FormatException('服务端字段 "$field" 不是数组');
    }
    final List<dynamic> items = rawItems;
    return items
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic> _requireMap(dynamic data, String endpoint) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data == null) {
      throw FormatException('服务端返回空响应：$endpoint');
    }
    throw FormatException('服务端返回格式不正确：$endpoint');
  }
}
