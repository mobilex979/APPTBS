// Export Excel: sheet SEMUA + sheet per supplier, lalu share
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

class ExcelExporter {
  static final headers = ['Tanggal','No Nota','Supplier','No Polisi','Sopir',
    'Bruto (kg)','Tara (kg)','Netto (kg)','Potongan','Netto Bersih (kg)',
    'Jml TBS/JJG','Harga/kg','Total (Rp)','Catatan'];

  static String _safe(String s) {
    for (var ch in ['[', ']', ':', '*', '?', '/', '\\']) {
      s = s.replaceAll(ch, ' ');
    }
    s = s.trim();
    if (s.isEmpty) s = 'TANPA_SUPPLIER';
    return s.length > 31 ? s.substring(0, 31) : s;
  }

  static Future<File> export(List<Map<String, dynamic>> rows, String tanggal) async {
    final wb = Workbook();
    wb.worksheets.clear();

    void fillSheet(String name, List<Map<String, dynamic>> data) {
      final ws = wb.worksheets.addWithName(_safe(name));
      for (var c = 0; c < headers.length; c++) {
        ws.getRangeByIndex(1, c + 1).setText(headers[c]);
      }
      for (var r = 0; r < data.length; r++) {
        final m = data[r];
        final vals = [
          m['tanggal'], m['no_nota'], m['supplier'], m['nopol'], m['sopir'],
          m['bruto'], m['tara'], m['netto'], m['potongan'], m['netto_bersih'],
          m['jjg'], m['harga'], m['total'], m['catatan']
        ];
        for (var c = 0; c < vals.length; c++) {
          final cell = ws.getRangeByIndex(r + 2, c + 1);
          if (vals[c] is num) {
            cell.setNumber(vals[c] as num);
          } else {
            cell.setText(vals[c]?.toString() ?? '');
          }
        }
      }
    }

    fillSheet('SEMUA', rows);
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (var m in rows) {
      grouped.putIfAbsent(m['supplier']?.toString() ?? 'TANPA_SUPPLIER', () => []).add(m);
    }
    grouped.forEach((s, list) => fillSheet(s, list));

    final bytes = wb.saveAsStream();
    wb.dispose();
    final dir = await getExternalStorageDirectory()
        ?? await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Nota_Timbang_$tanggal.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> exportAndShare(List<Map<String, dynamic>> rows, String tanggal) async {
    final f = await export(rows, tanggal);
    await Share.shareXFiles([XFile(f.path)], text: 'Rekap Nota Timbang $tanggal');
  }
}
