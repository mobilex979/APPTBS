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
        'perusahaan TEXT, tanggal TEXT, no_nota TEXT, supplier TEXT,'
        'nopol TEXT, sopir TEXT,'
        'bruto REAL, tara REAL, netto REAL, potongan REAL,'
        'netto_bersih REAL, jjg REAL, harga REAL, total REAL,'
        'file_foto TEXT, catatan TEXT,'
        'created_at TEXT DEFAULT CURRENT_TIMESTAMP)'
      ),
    );
    // migrasi: tambah kolom perusahaan untuk database lama
    final cols = await _db!.rawQuery('PRAGMA table_info(nota)');
    final names = cols.map((c) => c['name'] as String).toList();
    if (!names.contains('perusahaan')) {
      await _db!.execute('ALTER TABLE nota ADD COLUMN perusahaan TEXT');
    }
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

  // ═══ TUTUP BUKU ═══
  /// hapus data bulan sebelumnya; return keterangan jumlah yg dihapus
  static Future<String> hapusBulanSebelumnya(String bulanIni) async {
    await _ensurePanen();
    final dbx = await db;
    final n1 = await dbx.delete('nota',
        where: "substr(COALESCE(tanggal, created_at), 1, 7) < ?",
        whereArgs: [bulanIni]);
    final n2 = await dbx.delete('panen',
        where: "substr(COALESCE(tanggal, created_at), 1, 7) < ?",
        whereArgs: [bulanIni]);
    return 'nota $n1 & panen $n2 (bulan lalu) terhapus';
  }

  /// daftar bulan yang punya data (untuk pemilih riwayat)
  static Future<List<String>> bulanBulanAda() async {
    await _ensurePanen();
    final dbx = await db;
    final s = <String>{};
    for (final t in ['nota', 'panen']) {
      final r = await dbx.rawQuery(
          "SELECT DISTINCT substr(COALESCE(tanggal, created_at), 1, 7) b "
          "FROM $t WHERE COALESCE(tanggal, created_at) IS NOT NULL");
      s.addAll(r.map((m) => m['b'].toString()));
    }
    final list = s.toList()..sort();
    return list.reversed.toList();
  }

  // ═══ SARAN OTOMATIS (Opsi A): nilai unik dari riwayat nota ═══
  static const _kolomSaran = {'sopir', 'nopol', 'supplier', 'perusahaan'};

  static Future<List<String>> saran(String kolom, {int limit = 8}) async {
    if (!_kolomSaran.contains(kolom)) return const [];
    final r = await (await db).rawQuery(
        "SELECT $kolom v, COUNT(*) c FROM nota WHERE $kolom IS NOT NULL "
        "AND TRIM($kolom) <> '' GROUP BY $kolom ORDER BY c DESC, v LIMIT ?",
        [limit]);
    return r.map((m) => m['v'].toString()).toList();
  }

  // ═══ BACKUP & RESTORE (pindah HP / reinstall tanpa kehilangan data) ═══
  static Future<Map<String, dynamic>> backupAll() async {
    await _ensurePanen();
    final dbx = await db;
    return {
      'versi': 1,
      'aplikasi': 'BUSLIN BROS - Nota Timbang TBS',
      'waktu': DateTime.now().toIso8601String(),
      'nota': await dbx.query('nota'),
      'panen': await dbx.query('panen'),
    };
  }

  // id ikut dipulihkan agar link tiket_ids <-> nota tetap utuh
  static Future<int> restoreAll(Map<String, dynamic> data) async {
    await _ensurePanen();
    final dbx = await db;
    await dbx.delete('nota');
    await dbx.delete('panen');
    var n = 0;
    for (final row in (data['nota'] as List? ?? const [])) {
      await dbx.insert('nota', Map<String, dynamic>.from(row));
      n++;
    }
    for (final row in (data['panen'] as List? ?? const [])) {
      await dbx.insert('panen', Map<String, dynamic>.from(row));
      n++;
    }
    return n;
  }

  // daftar nomor tiket yang sudah tersimpan (untuk screening anti-double)
  static Future<Set<String>> noTiketTersimpan() async {
    final r = await (await db).query('nota', columns: ['no_nota']);
    return r
        .map((m) => m['no_nota']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet();
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
