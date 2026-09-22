// Ekstraksi field nota timbang TBS - disesuaikan untuk format
// Tiket Timbang PT Perlang Sawitindo Mas (NO TIKET / RELASI / PLAT NO /
// TARRA / BERAT / SORTASI %, tanggal "21 Sep 2026", harga "@3090")
class Nota {
  String? perusahaan;   // nama PT/CV/UD/PD di kepala nota
  String? tanggal, noNota, supplier, nopol, produk, sopir, jamMasuk, jamKeluar;
  double? bruto, tara, netto, potongan, berat, sortasi, jjg, harga, total;
  String fileFoto = '';
  String catatan = '';
  bool sudahAda = false;   // no tiket sudah tersimpan di database

  double? get nettoBersih => berat ??
      (netto != null ? netto! - (potongan ?? 0) : null);

  bool get perluCek =>
      supplier == null || bruto == null || tara == null || netto == null;

  Map<String, dynamic> toMap() => {
        'perusahaan': perusahaan,
        'tanggal': tanggal, 'no_nota': noNota, 'supplier': supplier,
        'nopol': nopol, 'sopir': sopir,
        'bruto': bruto, 'tara': tara, 'netto': netto, 'potongan': potongan,
        'netto_bersih': nettoBersih, 'jjg': jjg, 'harga': harga,
        'total': total, 'file_foto': fileFoto, 'catatan': catatan,
      };
}

class NotaParser {
  // Pola GENERIK — mengenal format nota dari perusahaan apa pun
  // (PT/CV/UD/PD, istilah tiket/nota/bukti, plat no/polisi/kendaraan, dll.)
  static final Map<String, RegExp> p = {
    'perusahaan': RegExp(
        r'^((?:PT|CV|UD|PD|YAYASAN)\.?\s+[A-Z0-9][A-Z0-9 .,&\-]{2,60})$',
        caseSensitive: false, multiLine: true),
    'no_nota': RegExp(
        r'(?:no\.?\s*(?:tiket|nota)|nomor\s*(?:tiket|nota)|tiket\s*no\.?|no\.?\s*(?:bukti|struk))\s*[:\-]?\s*([A-Za-z0-9][A-Za-z0-9\-\/]{2,})',
        caseSensitive: false),
    'tanggal': RegExp(
        r'(?:tanggal\s*cetak|tanggal|tgl\.?|date)\s*[:\-]?\s*(\d{1,2}\s+[A-Za-z]{3,}\s+\d{4})',
        caseSensitive: false),
    'tanggal2': RegExp(r'\b(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4})\b'),
    'supplier': RegExp(
        r'(?:relasi|supplier|nama\s*supplier|pemasok|mitra|petani|unit|kelompok|pengirim|afdeling|afd\.?)\s*[:\-]?\s*(.{2,60}?)(?=\s{2,}|\s+(?:tarr?a|netto|bruto|potongan|berat|jam|plat|produk|no|ket)\b|$)',
        caseSensitive: false),
    'nopol': RegExp(
        r'(?:plat\s*no|no\.?\s*pol(?:isi)?\.?|nomor\s*polisi|no\.?\s*kendaraan|no\.?\s*plat|nopol)\s*[:\-]?\s*([A-Za-z]{1,2}\s?\d{3,4}\s?[A-Za-z]{0,3})',
        caseSensitive: false),
    'produk': RegExp(r'produk\s*[:\-]?\s*([A-Za-z]{2,10})\b', caseSensitive: false),
    'sopir': RegExp(r'(?:sopir|supir|driver)\s*[:\-]?\s*([A-Za-z][A-Za-z .]{1,25})',
        caseSensitive: false),
    'bruto': RegExp(r'bruto\s*[:\-]?\s*([\d.,]+)', caseSensitive: false),
    'tara': RegExp(r'tarr?a\s*[:\-]?\s*([\d.,]+)', caseSensitive: false),
    'netto': RegExp(r'netto\s*[:\-]?\s*([\d.,]+)', caseSensitive: false),
    'potongan': RegExp(r'(?:potongan|sortasi\s*\(kg\))\s*[:\-]?\s*([\d.,]+)',
        caseSensitive: false),
    'berat': RegExp(r'berat(?:\s*bersih)?\s*[:\-]?\s*([\d.,]+)', caseSensitive: false),
    'netto_bersih': RegExp(r'netto\s*bersih\s*[:\-]?\s*([\d.,]+)',
        caseSensitive: false),
    'sortasi': RegExp(r'sortasi\s*[:\-]?\s*([\d.,]+)\s*%', caseSensitive: false),
    'harga': RegExp(r'@\s*([\d.,]{3,})|(?:harga)\s*[:\-]?\s*(?:rp\.?)?\s*([\d.,]+)',
        caseSensitive: false),
    'jjg': RegExp(r'(?:jjg|janjang)\s*[:\-]?\s*([\d.,]+)', caseSensitive: false),
    'jam_masuk': RegExp(r'jam\s*masuk\s*[:\-]?\s*([\d/ .:]+)', caseSensitive: false),
    'jam_keluar': RegExp(r'jam\s*keluar\s*[:\-]?\s*([\d/ .:]+)', caseSensitive: false),
  };

  static const _bulan = {
    'jan': '01', 'feb': '02', 'mar': '03', 'apr': '04', 'mei': '05',
    'may': '05', 'jun': '06', 'jul': '07', 'agu': '08', 'aug': '08',
    'sep': '09', 'okt': '10', 'oct': '10', 'nov': '11', 'des': '12',
    'dec': '12',
  };

  static String? _get2(String key, String text) {
    final m = p[key]!.firstMatch(text);
    if (m == null) return null;
    return (m.group(1) ?? m.group(2))?.trim();
  }

  static String? _get(String key, String text) =>
      p[key]!.firstMatch(text)?.group(1)?.trim();

  static double? _num(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    s = s.trim().replaceAll(' ', '');
    if (s.contains(',') && s.contains('.')) {
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        s = s.replaceAll('.', '').replaceAll(',', '.'); // 1.234,56 -> 1234.56
      } else {
        s = s.replaceAll(',', '');                      // 1,234.56 -> 1234.56
      }
    } else if (s.contains(',')) {
      final parts = s.split(',');
      if (parts.length == 2 && parts[1].length == 3) {
        s = s.replaceAll(',', '');   // 8,460 -> 8460 (ribuan, titik salah baca jadi koma)
      } else if (parts.length > 2) {
        s = s.replaceAll(',', '');   // 13,750,500 -> ribuan
      } else {
        s = s.replaceAll(',', '.');  // 4,60 -> 4.6 (desimal)
      }
    } else if (s.contains('.')) {
      final parts = s.split('.');
      if (parts.length == 2 && parts[1].length == 3) {
        s = s.replaceAll('.', '');   // 8.460 -> 8460 (pemisah ribuan)
      } else if (parts.length > 2) {
        s = s.replaceAll('.', '');   // 13.750.500 -> ribuan
      }
      // else: 4.60 -> 4.6 desimal (dibiarkan)
    }
    return double.tryParse(s);
  }

  static String? _parseTanggal(String? cetak, String? alternatif) {
    if (cetak != null) {
      final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3,})\s+(\d{4})')
          .firstMatch(cetak);
      if (m != null) {
        final bln = _bulan[m.group(2)!.substring(0, 3).toLowerCase()];
        if (bln != null) {
          return '${m.group(3)}-$bln-${m.group(1)!.padLeft(2, '0')}';
        }
      }
    }
    if (alternatif != null) {
      final m = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(alternatif);
      if (m != null) return '${m.group(3)}-${m.group(2)}-${m.group(1)}';
    }
    return null;
  }

  static Nota parse(String text, String fileFoto) {
    final n = Nota()
      ..perusahaan = _get('perusahaan', text)
      ..tanggal = _parseTanggal(_get('tanggal', text), _get('tanggal2', text))
      ..noNota = _get('no_nota', text)
      ..supplier = _get('supplier', text)
      ..nopol = _get('nopol', text)
      ..produk = _get('produk', text)
      ..sopir = _get('sopir', text)
      ..jamMasuk = _get('jam_masuk', text)
      ..jamKeluar = _get('jam_keluar', text)
      ..bruto = _num(_get('bruto', text))
      ..tara = _num(_get('tara', text))
      ..netto = _num(_get('netto', text))
      ..potongan = _num(_get('potongan', text))
      ..berat = _num(_get('berat', text) ?? _get('netto_bersih', text))
      ..sortasi = _num(_get('sortasi', text))
      ..jjg = _num(_get('jjg', text))
      ..harga = _num(_get2('harga', text))
      ..fileFoto = fileFoto;

    // Total = BERAT x HARGA (otomatis jika keduanya ada)
    if (n.berat != null && n.harga != null) {
      n.total = n.berat! * n.harga!;
    }
    final info = <String>[
      if (n.produk != null) 'Produk: ${n.produk}',
      if (n.sortasi != null) 'Sortasi: ${n.sortasi}%',
      if (n.jamMasuk != null) 'Masuk: ${n.jamMasuk}',
    ];
    n.catatan = n.perluCek
        ? 'CEK MANUAL${info.isEmpty ? '' : ' | ${info.join(' | ')}'}'
        : (info.isEmpty ? '' : info.join(' | '));
    return n;
  }
}
