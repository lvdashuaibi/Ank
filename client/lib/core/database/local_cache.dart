import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class LocalCache {
  LocalCache({this.databaseName = 'flashcard_app.db'});

  final String databaseName;
  Database? _database;

  Future<Database> get database async {
    final Database? existing = _database;
    if (existing != null) {
      return existing;
    }
    final String dbPath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(dbPath, databaseName),
      version: 4,
      onCreate: (Database db, int version) async {
        await _createTables(db);
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS sync_operations (
              id TEXT PRIMARY KEY,
              operation_type TEXT NOT NULL,
              payload TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS app_meta (
              key TEXT PRIMARY KEY,
              payload TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS folders (
              id TEXT PRIMARY KEY,
              payload TEXT NOT NULL
            )
          ''');
        }
      },
    );
    return _database!;
  }

  Future<List<Map<String, dynamic>>> loadFolders() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'folders',
      orderBy: 'id',
    );
    return rows.map(_decodePayload).toList();
  }

  Future<void> replaceFolders(List<Map<String, dynamic>> folders) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      await txn.delete('folders');
      for (final Map<String, dynamic> folder in folders) {
        await txn.insert('folders', <String, Object?>{
          'id': folder['id'] as String,
          'payload': jsonEncode(folder),
        });
      }
    });
  }

  Future<void> upsertFolder(Map<String, dynamic> folder) async {
    final Database db = await database;
    await db.insert('folders', <String, Object?>{
      'id': folder['id'] as String,
      'payload': jsonEncode(folder),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteFolder(String folderId) async {
    final Database db = await database;
    await db.delete('folders', where: 'id = ?', whereArgs: <Object?>[folderId]);
  }

  Future<List<Map<String, dynamic>>> loadDecks() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'decks',
      orderBy: 'id',
    );
    return rows.map(_decodePayload).toList();
  }

  Future<void> replaceDecks(List<Map<String, dynamic>> decks) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      await txn.delete('decks');
      for (final Map<String, dynamic> deck in decks) {
        await txn.insert('decks', <String, Object?>{
          'id': deck['id'] as String,
          'payload': jsonEncode(deck),
        });
      }
    });
  }

  Future<void> upsertDeck(Map<String, dynamic> deck) async {
    final Database db = await database;
    await db.insert('decks', <String, Object?>{
      'id': deck['id'] as String,
      'payload': jsonEncode(deck),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDeck(String deckId) async {
    final Database db = await database;
    await db.delete('decks', where: 'id = ?', whereArgs: <Object?>[deckId]);
  }

  Future<List<Map<String, dynamic>>> loadCards({String? deckId}) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'cards',
      where: deckId == null ? null : 'deck_id = ?',
      whereArgs: deckId == null ? null : <Object?>[deckId],
      orderBy: 'id',
    );
    return rows.map(_decodePayload).toList();
  }

  Future<void> replaceCards(List<Map<String, dynamic>> cards) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      await txn.delete('cards');
      for (final Map<String, dynamic> card in cards) {
        await txn.insert('cards', <String, Object?>{
          'id': card['id'] as String,
          'deck_id': card['deck_id'] as String,
          'payload': jsonEncode(card),
        });
      }
    });
  }

  Future<void> upsertCard(Map<String, dynamic> card) async {
    final Database db = await database;
    await db.insert('cards', <String, Object?>{
      'id': card['id'] as String,
      'deck_id': card['deck_id'] as String,
      'payload': jsonEncode(card),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCards(List<String> ids) async {
    if (ids.isEmpty) {
      return;
    }
    final Database db = await database;
    final String placeholders = List<String>.filled(ids.length, '?').join(',');
    await db.delete('cards', where: 'id IN ($placeholders)', whereArgs: ids);
  }

  Future<void> deleteCardsByDeck(String deckId) async {
    final Database db = await database;
    await db.delete(
      'cards',
      where: 'deck_id = ?',
      whereArgs: <Object?>[deckId],
    );
  }

  Future<void> clearAll() async {
    final Database db = await database;
    await db.delete('cards');
    await db.delete('decks');
    await db.delete('folders');
    await db.delete('sync_operations');
    await db.delete('app_meta');
  }

  Future<void> enqueueSyncOperation({
    required String id,
    required String operationType,
    required Map<String, dynamic> payload,
    required DateTime createdAt,
  }) async {
    final Database db = await database;
    await db.insert('sync_operations', <String, Object?>{
      'id': id,
      'operation_type': operationType,
      'payload': jsonEncode(payload),
      'created_at': createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> loadSyncOperations() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'sync_operations',
      orderBy: 'created_at ASC',
    );
    return rows.map((Map<String, Object?> row) {
      final dynamic decoded = jsonDecode(row['payload']! as String);
      return <String, dynamic>{
        'id': row['id'],
        'type': row['operation_type'],
        'payload': decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{},
        'occurred_at': row['created_at'],
      };
    }).toList();
  }

  Future<void> replaceSyncOperations(
    List<Map<String, dynamic>> operations,
  ) async {
    final Database db = await database;
    await db.transaction((Transaction txn) async {
      await txn.delete('sync_operations');
      for (final Map<String, dynamic> operation in operations) {
        await txn.insert('sync_operations', <String, Object?>{
          'id': operation['id'] as String,
          'operation_type': operation['type'] as String,
          'payload': jsonEncode(operation['payload']),
          'created_at': operation['occurred_at'] as String,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> removeSyncOperations(List<String> ids) async {
    if (ids.isEmpty) {
      return;
    }
    final Database db = await database;
    final String placeholders = List<String>.filled(ids.length, '?').join(',');
    await db.delete(
      'sync_operations',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<Map<String, dynamic>?> loadDailyProgress() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'app_meta',
      columns: const <String>['payload'],
      where: 'key = ?',
      whereArgs: const <Object?>['daily_progress'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _decodePayload(rows.first);
  }

  Future<void> saveDailyProgress(Map<String, dynamic> progress) async {
    final Database db = await database;
    await db.insert('app_meta', <String, Object?>{
      'key': 'daily_progress',
      'payload': jsonEncode(progress),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearDailyProgress() async {
    final Database db = await database;
    await db.delete(
      'app_meta',
      where: 'key = ?',
      whereArgs: const <Object?>['daily_progress'],
    );
  }

  Future<void> close() async {
    final Database? db = _database;
    if (db == null) {
      return;
    }
    await db.close();
    _database = null;
  }

  Future<void> deleteDatabaseFile() async {
    await close();
    final String dbPath = await getDatabasesPath();
    await deleteDatabase(path.join(dbPath, databaseName));
  }

  Map<String, dynamic> _decodePayload(Map<String, Object?> row) {
    final dynamic decoded = jsonDecode(row['payload']! as String);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE decks (
        id TEXT PRIMARY KEY,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE cards (
        id TEXT PRIMARY KEY,
        deck_id TEXT NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sync_operations (
        id TEXT PRIMARY KEY,
        operation_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE app_meta (
        key TEXT PRIMARY KEY,
        payload TEXT NOT NULL
      )
    ''');
  }
}
