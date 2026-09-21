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

  static Future<List<Map<String, dynamic>>> all() async =>
      (await db).query('nota', orderBy: 'id DESC');

  static Future<int> count() async =>
      Sqflite.firstIntValue(await (await db).rawQuery('SELECT COUNT(*) FROM nota')) ?? 0;

  static Future<int> delete(int id) async =>
      (await db).delete('nota', where: 'id = ?', whereArgs: [id]);
}
