import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'music.dart';

class ScoreStore {
  Database? _database;

  Future<Database> get database async => _database ??= await openDatabase(
    path.join(await getDatabasesPath(), 'solfeus.db'),
    version: 1,
    onCreate: (database, version) async {
      await database.execute(
        'CREATE TABLE scores (id INTEGER PRIMARY KEY AUTOINCREMENT, document TEXT NOT NULL, updated TEXT NOT NULL)',
      );
    },
  );

  Future<List<Score>> all() async {
    final rows = await (await database).query(
      'scores',
      orderBy: 'updated DESC',
    );
    return rows.map((row) => Score.decode(row['document'] as String)).toList();
  }

  Future<void> save(Score score) async {
    final db = await database;
    score.updated = DateTime.now();
    score.id ??= await db.insert('scores', {
      'document': score.encode(),
      'updated': score.updated.toIso8601String(),
    });
    await db.update(
      'scores',
      {'document': score.encode(), 'updated': score.updated.toIso8601String()},
      where: 'id = ?',
      whereArgs: [score.id],
    );
  }

  Future<void> delete(Score score) async {
    if (score.id != null) {
      await (await database).delete(
        'scores',
        where: 'id = ?',
        whereArgs: [score.id],
      );
    }
  }
}
