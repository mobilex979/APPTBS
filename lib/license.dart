// Sistem lisensi MODEL B — kode aktivasi TERIKAT pada HP (Kode HP unik).
// Kode 10 digit disusun dari: rahasia + Kode HP + tanggal kedaluwarsa.
// Kode dari HP lain TIDAK akan berfungsi.
// Generate kode: APK Generator (HP owner) atau gen_licensi.py.
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_id/android_id.dart';
import 'db_helper.dart';
import 'package:encrypt/encrypt.dart' as enc;

class License {
  static const String _secret = 'BUSLINBROS-RAHASIA-2026';
  static const String _keyAktif = 'lisensi_aktif';
  static const String _keyKode = 'lisensi_kode';
  static const _androidId = AndroidId();

  /// Kode unik HP (8 karakter, dari Android ID yang di-hash).
  /// Ditampilkan di layar aktivasi; pemilik app memakainya utk generate kode.
  static Future<String> kodeHP() async {
    try {
      final id = await _androidId.getId() ?? 'unknown';
      return sha256
          .convert(utf8.encode(id))
          .toString()
          .substring(0, 8)
          .toUpperCase();
    } catch (_) {
      return '????????';
    }
  }

  static String _kodeUntuk(String device, DateTime tgl) {
    final days =
        DateTime(tgl.year, tgl.month, tgl.day).millisecondsSinceEpoch ~/
            86400000;
    final h =
        sha256.convert(utf8.encode('$_secret|$device|$days')).toString();
    var digits = '';
    for (final ch in h.codeUnits) {
      if (ch >= 48 && ch <= 57) digits += String.fromCharCode(ch);
      if (digits.length == 10) break;
    }
    return digits;
  }

  /// validasi kode untuk HP INI; return tanggal kedaluwarsa (null = salah)
  static Future<DateTime?> cek(String kode) async {
    final dev = await kodeHP();
    final k = kode.trim();
    final now = DateTime.now();
    for (var i = -30; i <= 365 * 6; i++) {
      final tgl = now.add(Duration(days: i));
      if (_kodeUntuk(dev, tgl) == k) return tgl;
    }
    return null;
  }

  static Future<void> simpan(String kode) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyAktif, true);
    await p.setString(_keyKode, kode.trim());
  }

  static Future<bool> sudahAktif() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_keyAktif) != true) return false;
    final exp = await cek(p.getString(_keyKode) ?? '');
    return exp != null && exp.isAfter(DateTime.now());
  }

  static Future<DateTime?> kedaluwarsa() async {
    final p = await SharedPreferences.getInstance();
    return cek(p.getString(_keyKode) ?? '');
  }

  static Future<void> hapus() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_keyAktif);
    await p.remove(_keyKode);
  }
}

// ═══ PROFIL MANDOR PERANGKAT — HP dikunci untuk 1 mandor ═══
class Profil {
  static const String _keyMandor = 'nama_mandor';

  static Future<String?> namaMandor() async {
    final p = await SharedPreferences.getInstance();
    final m = p.getString(_keyMandor);
    return (m == null || m.trim().isEmpty) ? null : m.trim();
  }

  static Future<void> simpanMandor(String nama) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_keyMandor, nama.trim());
  }
}

// ═══════════════════════════════════════════════════════════
// KONFIGURASI VERSI APK — ganti nilai di bawah lalu rebuild:
//   true  = VERSI 1: data bulan lalu TERHAPUS otomatis setelah export
//   false = VERSI 2: data bulan lalu DISEMBUNYIKAN (kode riwayat)
const bool VERSI_HAPUS_OTOMATIS = false;

// Kode supervisor untuk melihat riwayat bulan lalu (Versi 2)
const String KODE_RIWAYAT = 'hs123456';

// ═══ TUTUP BUKU: kunci TIAP SENIN, hapus data bulan lalu TIAP TANGGAL 1 ═══
class TutupBuku {
  static const String _keyLast = 'last_backup_minggu';

  static String _mingguIni(DateTime t) {
    final monday = t.subtract(Duration(days: t.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  /// true = HARI SENIN & minggu ini belum kirim backup -> input dikunci
  static Future<bool> perluKunci() async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    if (now.weekday != 1) return false;
    return (p.getString(_keyLast) ?? '') != _mingguIni(now);
  }

  // alias kompatibilitas: nama lama (jangan dipakai di kode baru)
  static Future<String?> tandaExport() => tandaiBackup();
  static Future<String?> tandaiExport() => tandaiBackup();

  /// dipanggil setelah backup (V1) / export (V2) berhasil.
  /// V1 + tanggal 1 -> hapus data bulan sebelumnya.
  static Future<String?> tandaiBackup() async {
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await p.setString(_keyLast, _mingguIni(now));
    if (VERSI_HAPUS_OTOMATIS && now.day == 1) {
      return await DBHelper.hapusBulanSebelumnya(
          '${now.year}-${now.month.toString().padLeft(2, '0')}');
    }
    return null;
  }
}

// ═══ ENKRIPSI FILE BACKUP (kunci = KODE_RIWAYAT hs123456) ═══
String enkripBackup(String json) {
  final key = enc.Key(Uint8List.fromList(sha256.convert(utf8.encode(KODE_RIWAYAT)).bytes));
  final iv = enc.IV.fromLength(16);
  final e = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  return e.encrypt(json, iv: iv).base64;
}

/// return plaintext, atau null bila file bukan backup valid / kode beda
String? dekripBackup(String data) {
  try {
    final key = enc.Key(Uint8List.fromList(sha256.convert(utf8.encode(KODE_RIWAYAT)).bytes));
    final iv = enc.IV.fromLength(16);
    final e = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    return e.decrypt64(data.trim(), iv: iv);
  } catch (_) {
    return null;
  }
}

// ═══ SESI LIHAT BULAN (Versi 2) — reset otomatis saat app ditutup ═══
class SesiBulan {
  static bool riwayatTerbuka = false;      // kode hs123456 sudah dimasukkan
  static String? bulanDipilih;             // 'YYYY-MM' atau null = bulan berjalan
}
