// Export Excel: sheet SEMUA + sheet per supplier, lalu share
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';
import 'package:archive/archive.dart';

// KODE AKSES file export — hanya yang tahu kode ini yang bisa membuka ZIP.
// Ganti sesuai keinginan, lalu rebuild.
const String KODE_AKSES = 'bros1234';

class ExcelExporter {
  static final headers = ['Tanggal','No Nota','Supplier','Perusahaan/PKS','No Polisi','Sopir',
    'Bruto (kg)','Tara (kg)','Netto (kg)','Potongan','Netto Bersih (kg)',
    'Jml TBS/JJG','Blok','Catatan'];

  static String _safe(String s) {
    for (var ch in ['[', ']', ':', '*', '?', '/', '\\']) {
      s = s.replaceAll(ch, ' ');
    }
    s = s.trim();
    if (s.isEmpty) s = 'TANPA_SUPPLIER';
    return s.length > 31 ? s.substring(0, 31) : s;
  }

  static Future<File> export(List<Map<String, dynamic>> rows, String tanggal,
      {List<Map<String, dynamic>>? panen}) async {
    final wb = Workbook();
    wb.worksheets.clear();

    // peta id nota -> blok (dari tiket_ids panen yang terhubung)
    final blokOf = <int, String>{};
    final notaById = <int, Map<String, dynamic>>{};
    for (final n in rows) { notaById[n['id'] as int] = n; }
    for (final p in panen ?? const <Map<String, dynamic>>[]) {
      for (final tid in (p['tiket_ids']?.toString() ?? '').split(',')) {
        final id = int.tryParse(tid.trim());
        if (id != null) blokOf[id] = p['blok']?.toString() ?? '';
      }
    }

    Worksheet fillSheet(String name, List<Map<String, dynamic>> data) {
      final ws = wb.worksheets.addWithName(_safe(name));
      for (var c = 0; c < headers.length; c++) {
        ws.getRangeByIndex(1, c + 1).setText(headers[c]);
      }
      for (var r = 0; r < data.length; r++) {
        final m = data[r];
        final vals = [
          m['tanggal'], m['no_nota'], m['supplier'], m['perusahaan'], m['nopol'], m['sopir'],
          m['bruto'], m['tara'], m['netto'], m['potongan'], m['netto_bersih'],
          m['jjg'], blokOf[m['id']] ?? '', m['catatan']
        ];
        for (var c = 0; c < vals.length; c++) {
          final cell = ws.getRangeByIndex(r + 2, c + 1);
          final v = vals[c];
          if (v is num) {
            cell.setNumber(v.toDouble());
          } else {
            cell.setText(v?.toString() ?? '');
          }
        }
      }
      return ws;
    }

    final wsSemua = fillSheet('SEMUA', rows);
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (var m in rows) {
      grouped.putIfAbsent(m['supplier']?.toString() ?? 'TANPA_SUPPLIER', () => []).add(m);
    }
    grouped.forEach((s, list) => fillSheet(s, list));

    // REKAP: rata-rata kg per janjang (timbang vs panen)
    final totBerat = rows.fold<double>(
        0, (a, m) => a + (m['netto_bersih'] as num? ?? 0));
    final totJjg = (panen ?? []).fold<double>(
        0, (a, m) => a + (m['jjg'] as num? ?? 0));
    final avg = totJjg > 0 ? totBerat / totJjg : null;

    final r0 = rows.length + 3;
    wsSemua.getRangeByIndex(r0, 1).setText('REKAP TIMBANG vs PANEN');
    wsSemua.getRangeByIndex(r0 + 1, 1).setText('Total Berat Bersih (kg)');
    wsSemua.getRangeByIndex(r0 + 1, 2).setNumber(totBerat);
    wsSemua.getRangeByIndex(r0 + 2, 1).setText('Total Janjang Panen (jjg)');
    wsSemua.getRangeByIndex(r0 + 2, 2).setNumber(totJjg);
    wsSemua.getRangeByIndex(r0 + 3, 1).setText('Rata-rata (kg/JJG)');
    if (avg != null) {
      wsSemua.getRangeByIndex(r0 + 3, 2)
          .setNumber(double.parse(avg.toStringAsFixed(2)));
    } else {
      wsSemua.getRangeByIndex(r0 + 3, 2).setText('isi data panen dulu');
    }

    // Sheet PANEN: janjang per blok (input di lapangan)
    Worksheet? wsPanen;
    if (panen != null && panen.isNotEmpty) {
      const panenHeaders = ['Tanggal', 'Blok', 'Jml Janjang', 'Mandor',
          'Tiket Terhubung', 'Berat Terhubung (kg)', 'Avg kg/JJG (blok)',
          'Keterangan', 'Waktu Input'];
      wsPanen = wb.worksheets.addWithName('PANEN');
      final ws = wsPanen!;
      for (var c = 0; c < panenHeaders.length; c++) {
        ws.getRangeByIndex(1, c + 1).setText(panenHeaders[c]);
      }
      for (var r = 0; r < panen.length; r++) {
        final m = panen[r];
        final ids = (m['tiket_ids']?.toString() ?? '')
            .split(',')
            .map((x) => int.tryParse(x.trim()))
            .whereType<int>()
            .toList();
        var beratLinked = 0.0;
        final tiketLabels = <String>[];
        for (final id in ids) {
          final n = notaById[id];
          if (n != null) {
            beratLinked += (n['netto_bersih'] as num? ?? 0);
            tiketLabels.add(n['no_nota']?.toString() ?? '#$id');
          }
        }
        final jjg = (m['jjg'] as num? ?? 0).toDouble();
        final avgBlok = (jjg > 0 && beratLinked > 0)
            ? double.parse((beratLinked / jjg).toStringAsFixed(2))
            : null;
        final vals = [m['tanggal'], m['blok'], m['jjg'], m['mandor'],
            tiketLabels.join(', '), beratLinked, avgBlok,
            m['keterangan'], m['created_at']];
        for (var c = 0; c < vals.length; c++) {
          final cell = ws.getRangeByIndex(r + 2, c + 1);
          final v = vals[c];
          if (v is num) {
            cell.setNumber(v.toDouble());
          } else {
            cell.setText(v?.toString() ?? '');
          }
        }
      }
    }

    // REKAP rata-rata kg/JJG juga di sheet PANEN
    if (wsPanen != null && rows.isNotEmpty) {
      final rp = panen!.length + 3;
      wsPanen.getRangeByIndex(rp, 1).setText('REKAP TIMBANG vs PANEN');
      wsPanen.getRangeByIndex(rp + 1, 1).setText('Total JJG Panen');
      wsPanen.getRangeByIndex(rp + 1, 3).setNumber(totJjg);
      wsPanen.getRangeByIndex(rp + 2, 1).setText('Total Berat Bersih Timbang (kg)');
      wsPanen.getRangeByIndex(rp + 2, 3).setNumber(totBerat);
      wsPanen.getRangeByIndex(rp + 3, 1).setText('Rata-rata (kg/JJG)');
      if (avg != null) {
        wsPanen.getRangeByIndex(rp + 3, 3)
            .setNumber(double.parse(avg.toStringAsFixed(2)));
      } else {
        wsPanen.getRangeByIndex(rp + 3, 3).setText('-');
      }
    }

    final bytes = wb.saveAsStream();
    wb.dispose();
    final dir = await getExternalStorageDirectory()
        ?? await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Nota_Timbang_$tanggal.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> exportAndShare(List<Map<String, dynamic>> rows, String tanggal,
      {List<Map<String, dynamic>>? panen}) async {
    final f = await export(rows, tanggal, panen: panen);
    // bungkus dalam ZIP berpassword — hanya yang tahu kode yang bisa buka
    final bytes = await f.readAsBytes();
    final archive = Archive();
    archive.addFile(ArchiveFile(
        'Nota_Timbang_$tanggal.xlsx', bytes.length, bytes));
    final zipBytes = ZipEncoder(password: KODE_AKSES).encode(archive);
    final zipFile = File('${f.parent.path}/Nota_Timbang_$tanggal.ZIP');
    await zipFile.writeAsBytes(zipBytes!, flush: true);
    await Share.shareXFiles([XFile(zipFile.path)],
        text: 'Rekap Nota Timbang $tanggal (ZIP berkode — tanya supervisor)');
  }
}
