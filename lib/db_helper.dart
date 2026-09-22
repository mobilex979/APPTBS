// Database SQLite: simpan nota harian
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'nota_parser.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), 'nota_tbs.db'),
      version: 1,
      onCreate: (d, v) => d.execute(
        'CREATE TABLE nota('
        'id INTEGER PRIMARY KEY AUTOINCREMENT,'
        'tanggal TEXT, no_nota TEXT, supplier TEXT,'
        'nopol TEXT, sopir TEXT,'
        'bruto REAL, tara REAL, netto REAL, potongan REAL,'
        'netto_bersih REAL, jjg REAL, harga REAL, total REAL,'
        'file_foto TEXT, catatan TEXT,'
        'created_at TEXT DEFAULT CURRENT_TIMESTAMP)'
      ),
    );
    return _db!;
  }

  static Future<int> insert(Nota n) async =>
      (await db).insert('nota', n.toMap());

  static Future<int> update(int id, Map<String, dynamic> values) async =>
      (await db).update('nota', values, where: 'id = ?', whereArgs: [id]);

  static Future<List<Map<String, dynamic>>> all() async =>
      (await db).query('nota', orderBy: 'id DESC');

  static Future<int> count() async =>
      Sqflite.firstIntValue(await (await db).rawQuery('SELECT COUNT(*) FROM nota')) ?? 0;

  static Future<int> delete(int id) async =>
      (await db).delete('nota', where: 'id = ?', whereArgs: [id]);

  // ═══ PANEN: janjang per blok (dilakukan di lapangan sebelum loading) ═══
  static Future<void> _ensurePanen() async {
    await (await db).execute(
      'CREATE TABLE IF NOT EXISTS panen('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'tanggal TEXT, blok TEXT, jjg REAL, mandor TEXT,'
      'keterangan TEXT,'
      'created_at TEXT DEFAULT CURRENT_TIMESTAMP)');
  }

  static Future<int> insertPanen(Map<String, dynamic> m) async {
    await _ensurePanen();
    return (await db).insert('panen', m);
  }

  static Future<List<Map<String, dynamic>>> allPanen() async {
    await _ensurePanen();
    return (await db).query('panen', orderBy: 'id DESC');
  }

  static Future<int> deletePanen(int id) async {
    await _ensurePanen();
    return (await db).delete('panen', where: 'id = ?', whereArgs: [id]);
  }
}
