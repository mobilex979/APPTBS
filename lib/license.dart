// Sistem lisensi offline BUSLIN BROS
// Kode lisensi 10 digit menyandikan tanggal kedaluwarsa.
// Validasi offline: aplikasi menghitung ulang kode untuk rentang tanggal
// dan membandingkan. Kode baru dibuat dengan gen_licensi.py (di root repo).
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class License {
  static const String _secret = 'BUSLINBROS-RAHASIA-2026';
  static const String _keyAktif = 'lisensi_aktif';
  static const String _keyKode = 'lisensi_kode';

  static String _kodeUntuk(DateTime tgl) {
    final days = DateTime(tgl.year, tgl.month, tgl.day)
            .millisecondsSinceEpoch ~/
        86400000;
    final h = sha256.convert(utf8.encode('$_secret-$days')).toString();
    var digits = '';
    for (final ch in h.codeUnits) {
      if (ch >= 48 && ch <= 57) digits += String.fromCharCode(ch);
      if (digits.length == 10) break;
    }
    return digits;
  }

  /// cek kode valid & kembalikan tanggal kedaluwarsanya (null = tidak valid)
  static DateTime? cek(String kode) {
    final k = kode.trim();
    final now = DateTime.now();
    for (var i = -30; i <= 365 * 6; i++) {
      final tgl = now.add(Duration(days: i));
      if (_kodeUntuk(tgl) == k) return tgl;
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
    final kode = p.getString(_keyKode) ?? '';
    final exp = cek(kode);
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
