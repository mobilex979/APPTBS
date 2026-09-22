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
    final d = await db;
    await d.execute(
      'CREATE TABLE IF NOT EXISTS panen('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'tanggal TEXT, blok TEXT, jjg REAL, mandor TEXT,'
      'keterangan TEXT, tiket_ids TEXT,'
      'created_at TEXT DEFAULT CURRENT_TIMESTAMP)');
    // migrasi untuk instal lama: tambah kolom tiket_ids kalau belum ada
    final cols = await d.rawQuery('PRAGMA table_info(panen)');
    final names = cols.map((c) => c['name'] as String).toList();
    if (!names.contains('tiket_ids')) {
      await d.execute('ALTER TABLE panen ADD COLUMN tiket_ids TEXT');
    }
  }

  // simpan daftar id nota yang terhubung ke catatan panen (dipisah koma)
  static Future<int> linkTiket(int panenId, String tiketIds) async {
    await _ensurePanen();
    return (await db).update('panen', {'tiket_ids': tiketIds},
        where: 'id = ?', whereArgs: [panenId]);
  }

  static Future<int> insertPanen(Map<String, dynamic> m) async {
    await _ensurePanen();
    return (await db).insert('panen', m);
  }

  static Future<List<Map<String, dynamic>>> allPanen() async {
    await _ensurePanen();
    return (await db).query('panen', orderBy: 'id DESC');
  }

  static Future<int> updatePanen(int id, Map<String, dynamic> values) async {
    await _ensurePanen();
    return (await db).update('panen', values,
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> deletePanen(int id) async {
    await _ensurePanen();
    return (await db).delete('panen', where: 'id = ?', whereArgs: [id]);
  }
}
