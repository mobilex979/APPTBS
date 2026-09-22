// Aplikasi Buslin Bross - Nota Timbang TBS (layar utama)
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'db_helper.dart';
import 'excel_exporter.dart';
import 'nota_parser.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Buslin Bross - Nota Timbang TBS',
        theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final picker = ImagePicker();
  final List<Nota> draft = [];   // hasil OCR yang belum disimpan
  bool loading = false;
  int savedCount = 0;
  List<Map<String, dynamic>> savedRows = [];
  List<Map<String, dynamic>> panenRows = [];

  @override
  void initState() {
    super.initState();
    _refreshCount();
    _loadSaved();
  }

  // format ribuan Indonesia: 8460 -> "8.460"
  String fmtNum(dynamic v) =>
      v == null ? '-' : NumberFormat('#,##0', 'id_ID').format(v);

  Future<void> _loadSaved() => _refreshCount();

  Future<void> _refreshCount() async {
    final c = await DBHelper.count();
    savedRows = await DBHelper.all();
    panenRows = await DBHelper.allPanen();
    if (mounted) setState(() => savedCount = c);
  }

  // Nilai kualitas hasil OCR: keyword nota + jumlah field berhasil diekstrak
  int _scoreOcr(String text) {
    var score = 0;
    final up = text.toUpperCase();
    for (final k in ['BRUTO', 'TARRA', 'TARA', 'NETTO', 'BERAT',
        'TIKET', 'RELASI', 'PLAT NO', 'SORTASI']) {
      if (up.contains(k)) score += 2;
    }
    final n = NotaParser.parse(text, '');
    if (n.noNota != null) score += 2;
    if (n.supplier != null) score += 3;
    if (n.bruto != null) score += 3;
    if (n.tara != null) score += 3;
    if (n.netto != null) score += 3;
    if (n.berat != null) score += 2;
    return score;
  }

  // OCR dengan auto-rotate: coba 4 arah putaran (0/90/180/270),
  // ambil hasil dengan skor tertinggi (atasi foto nota miring/terbalik)
  Future<String> _ocr(String path) async {
    final bytes = await File(path).readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) return '';
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final tmpDir = await getTemporaryDirectory();
    String bestText = '';
    var bestScore = -1;
    try {
      for (var r = 0; r < 4; r++) {
        if (r > 0) image = img.copyRotate(image!, angle: 90);
        final tmp = File('${tmpDir.path}/ocr_rot$r.jpg');
        await tmp.writeAsBytes(img.encodeJpg(image!, quality: 90));
        final res =
            await recognizer.processImage(InputImage.fromFilePath(tmp.path));
        final score = _scoreOcr(res.text);
        if (score > bestScore) {
          bestScore = score;
          bestText = res.text;
        }
      }
    } finally {
      recognizer.close();
    }
    return bestText;
  }

  Future<void> _prosesGambar(List<XFile> files) async {
    if (files.isEmpty) return;
    setState(() => loading = true);
    for (final f in files) {
      final text = await _ocr(f.path);
      setState(() => draft.add(NotaParser.parse(text, f.name)));
    }
    setState(() => loading = false);
  }

  Future<void> _dariKamera() async {
    final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (f != null) _prosesGambar([f]);
  }

  // PILIH BANYAK FOTO DARI GALERI SEKALIGUS
  Future<void> _dariGaleri() async {
    final files = await picker.pickMultiImage(imageQuality: 90);
    _prosesGambar(files);
  }

  Future<void> _simpanSemua() async {
    for (final n in draft) {
      await DBHelper.insert(n);
    }
    setState(() => draft.clear());
    await _refreshCount();
    await _loadSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Semua nota tersimpan.')));
    }
  }

  // HAPUS SEMUA DATA + FILE EXCEL (dengan konfirmasi dulu)
  Future<void> _hapusSemua() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus semua data?'),
        content: const Text(
            'Semua nota tersimpan dan file Excel hasil export akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;

    final d = await DBHelper.db;
    await d.delete('nota');   // hapus semua baris tabel

    // hapus file Excel hasil export (Nota_Timbang_*.xlsx)
    try {
      final dir = await getExternalStorageDirectory()
          ?? await getApplicationDocumentsDirectory();
      for (final f in dir.listSync()) {
        if (f is File && f.path.contains('Nota_Timbang_') && f.path.endsWith('.xlsx')) {
          f.deleteSync();
        }
      }
    } catch (_) {}

    await _refreshCount();
    await _loadSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Semua data & file Excel dihapus.')));
    }
  }

  // FORM INPUT MANUAL (tanpa kamera/galeri)
  Future<void> _inputManual() async {
    final tgl = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final noNota = TextEditingController();
    final supplier = TextEditingController();
    final nopol = TextEditingController();
    final sopir = TextEditingController();
    final bruto = TextEditingController();
    final tara = TextEditingController();
    final netto = TextEditingController();
    final potongan = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Input Nota Manual'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(controller: tgl,
                decoration: const InputDecoration(labelText: 'Tanggal (YYYY-MM-DD)')),
            TextField(controller: noNota,
                decoration: const InputDecoration(labelText: 'No Tiket')),
            TextField(controller: supplier,
                decoration: const InputDecoration(labelText: 'Supplier / Relasi')),
            TextField(controller: nopol,
                decoration: const InputDecoration(labelText: 'Plat No')),
            TextField(controller: sopir,
                decoration: const InputDecoration(labelText: 'Nama Supir')),
            TextField(controller: bruto, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Bruto (kg)')),
            TextField(controller: tara, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tara (kg)')),
            TextField(controller: netto, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Netto (kg)')),
            TextField(controller: potongan, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Potongan (kg)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tambah')),
        ],
      ),
    );
    if (ok == true) {
      final n = Nota()
        ..tanggal = tgl.text.trim().isEmpty ? null : tgl.text.trim()
        ..noNota = noNota.text.trim().isEmpty ? null : noNota.text.trim()
        ..supplier = supplier.text.trim().isEmpty ? null : supplier.text.trim()
        ..nopol = nopol.text.trim().isEmpty ? null : nopol.text.trim()
        ..sopir = sopir.text.trim().isEmpty ? null : sopir.text.trim()
        ..bruto = double.tryParse(bruto.text)
        ..tara = double.tryParse(tara.text)
        ..netto = double.tryParse(netto.text)
        ..potongan = double.tryParse(potongan.text)
        ..catatan = 'INPUT MANUAL';
      setState(() => draft.add(n));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nota manual ditambahkan ke daftar. Klik Simpan untuk menyimpan.')));
      }
    }
  }

  Future<void> _exportExcel() async {
    final rows = await DBHelper.all();
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada data.')));
      return;
    }
    final tgl = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final panen = await DBHelper.allPanen();
    await ExcelExporter.exportAndShare(rows, tgl, panen: panen);
  }

  Future<void> _edit(Nota n) async {
    final supplier = TextEditingController(text: n.supplier);
    final bruto = TextEditingController(text: n.bruto?.toString() ?? '');
    final tara = TextEditingController(text: n.tara?.toString() ?? '');
    final netto = TextEditingController(text: n.netto?.toString() ?? '');
    final jjg = TextEditingController(text: n.jjg?.toString() ?? '');
    final noNota = TextEditingController(text: n.noNota);
    final sopir = TextEditingController(text: n.sopir);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cek / Edit Nota'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(controller: supplier,
                decoration: const InputDecoration(labelText: 'Supplier')),
            TextField(controller: noNota,
                decoration: const InputDecoration(labelText: 'No Tiket')),
            TextField(controller: sopir,
                decoration: const InputDecoration(labelText: 'Nama Supir')),
            TextField(controller: bruto, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Bruto (kg)')),
            TextField(controller: tara, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tara (kg)')),
            TextField(controller: netto, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Netto (kg)')),
            TextField(controller: jjg, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Jml TBS/JJG')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        n.supplier = supplier.text.isEmpty ? null : supplier.text;
        n.noNota = noNota.text;
        n.sopir = sopir.text.isEmpty ? null : sopir.text;
        n.bruto = double.tryParse(bruto.text);
        n.tara = double.tryParse(tara.text);
        n.netto = double.tryParse(netto.text);
        n.jjg = double.tryParse(jjg.text);
        n.catatan = n.perluCek ? 'CEK MANUAL' : '';
      });
    }
  }

  // INPUT MANUAL (NEW): ketik data timbang tanpa kamera/galeri
  
  Future<void> _bukaDataTersimpan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SavedPage()),
    );
    await _refreshCount();
    await _loadSaved();
  }

  // TABEL REKAP DATA TERSIMPAN di halaman utama
  Widget _buildRekap() {
    if (savedRows.isEmpty) {
      return const Center(child: Text(
          'Belum ada data. Ambil foto nota atau pilih banyak foto dari galeri.',
          textAlign: TextAlign.center));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(children: [
          const Icon(Icons.table_chart, size: 18, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rekap Tersimpan: $savedCount nota',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(
                () {
                  final totBerat = savedRows.fold<double>(0,
                      (a, m) => a + (m['netto_bersih'] as num? ?? 0));
                  final totJjg = panenRows.fold<double>(0,
                      (a, m) => a + (m['jjg'] as num? ?? 0));
                  final avg = totJjg > 0 ? totBerat / totJjg : null;
                  return 'Total: ${fmtNum(totBerat)} kg \u2022 '
                      'Panen ${fmtNum(totJjg)} jjg \u2022 '
                      'Avg: ${avg != null ? avg.toStringAsFixed(1) : '-'} kg/JJG';
                }(),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ]),
          ),
        ]),
      ),
      const Divider(),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.green[50]),
              columns: const [
                DataColumn(label: Text('No Tiket')),
                DataColumn(label: Text('Plat No')),
                DataColumn(label: Text('Supir')),
                DataColumn(label: Text('Bruto'), numeric: true),
                DataColumn(label: Text('Tarra'), numeric: true),
                DataColumn(label: Text('Potongan'), numeric: true),
                DataColumn(label: Text('Berat Bersih'), numeric: true),
              ],
              rows: [
                for (final m in savedRows)
                  DataRow(cells: [
                    DataCell(Text(m['no_nota']?.toString() ?? '-')),
                    DataCell(Text(m['nopol']?.toString() ?? '-')),
                    DataCell(Text(m['sopir']?.toString() ?? '-')),
                    DataCell(Text(fmtNum(m['bruto']))),
                    DataCell(Text(fmtNum(m['tara']))),
                    DataCell(Text(fmtNum(m['potongan']))),
                    DataCell(Text(fmtNum(m['netto_bersih']),
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                  ]),
              ],
            ),
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Klik "Tersimpan" di atas untuk review & edit detail',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Buslin Bross'),
            Text('Nota Timbang TBS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          // TOMBOL PANEN (janjang per blok)
          IconButton(
            icon: const Icon(Icons.park),
            tooltip: 'Panen - janjang per blok',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PanenPage())),
          ),
          // TOMBOL HAPUS SEMUA DATA + FILE EXCEL
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Hapus semua data',
            onPressed: savedCount == 0 ? null : _hapusSemua,
          ),
          // COUNTER TERSIMPAN = TOMBOL BUKA DATA TERSIMPAN
          InkWell(
            onTap: _bukaDataTersimpan,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(child: Text('Tersimpan: $savedCount')),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Membaca nota...'),
            ]))
          : draft.isEmpty
              ? _buildRekap()
              : ListView.builder(
                  itemCount: draft.length,
                  itemBuilder: (ctx, i) {
                    final n = draft[i];
                    return Card(
                      color: n.perluCek ? Colors.red[50] : null,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text(n.supplier ?? '(supplier kosong)'),
                        subtitle: Text(
                          'Nota: ${n.noNota ?? '-'} | '
                          'Bruto: ${n.bruto ?? '-'} | Tara: ${n.tara ?? '-'} | '
                          'Netto: ${n.netto ?? '-'} kg',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _edit(n),
                        ),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: FilledButton.icon(
                onPressed: _dariKamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Kamera'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton.tonalIcon(
                onPressed: _dariGaleri,
                icon: const Icon(Icons.photo_library),
                label: const Text('Galeri (banyak)'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
                onPressed: draft.isEmpty ? null : _simpanSemua,
                icon: const Icon(Icons.save),
                label: Text('Simpan (${draft.length})'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
                onPressed: _exportExcel,
                icon: const Icon(Icons.table_chart),
                label: const Text('Export Excel'))),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _inputManual,
              icon: const Icon(Icons.edit_note),
              label: const Text('New - Input Manual (tanpa kamera)'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════ LAYAR REVIEW DATA TERSIMPAN (bisa edit & hapus per baris) ═══════════
class SavedPage extends StatefulWidget {
  const SavedPage({super.key});
  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> {
  List<Map<String, dynamic>> rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    rows = await DBHelper.all();
    setState(() {});
  }

  String _fmt(dynamic v) => v == null ? '-' : v.toString();

  bool selectMode = false;
  final Set<int> selected = {};

  Future<void> _hapusTerpilih() async {
    if (selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus ${selected.length} nota terpilih?'),
        content: const Text('Data yang dihapus tidak bisa dikembalikan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) {
      for (final id in selected) {
        await DBHelper.delete(id);
      }
      setState(() { selected.clear(); selectMode = false; });
      await _load();
    }
  }

  Future<void> _editRow(Map<String, dynamic> m) async {
    final supplier = TextEditingController(text: m['supplier']?.toString());
    final noNota = TextEditingController(text: m['no_nota']?.toString());
    final sopir = TextEditingController(text: m['sopir']?.toString());
    final bruto = TextEditingController(text: m['bruto']?.toString());
    final tara = TextEditingController(text: m['tara']?.toString());
    final netto = TextEditingController(text: m['netto']?.toString());
    final berat = TextEditingController(text: m['netto_bersih']?.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Nota #${m['id']}'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(controller: supplier,
                decoration: const InputDecoration(labelText: 'Supplier')),
            TextField(controller: noNota,
                decoration: const InputDecoration(labelText: 'No Tiket')),
            TextField(controller: sopir,
                decoration: const InputDecoration(labelText: 'Nama Supir')),
            TextField(controller: bruto, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Bruto (kg)')),
            TextField(controller: tara, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tara (kg)')),
            TextField(controller: netto, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Netto (kg)')),
            TextField(controller: berat, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Berat Bersih (kg)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true) {
      final b = double.tryParse(bruto.text);
      final t = double.tryParse(tara.text);
      final n = double.tryParse(netto.text);
      final bb = double.tryParse(berat.text);
      await DBHelper.update(m['id'] as int, {
        'supplier': supplier.text.isEmpty ? null : supplier.text,
        'no_nota': noNota.text,
        'sopir': sopir.text.isEmpty ? null : sopir.text,
        'bruto': b, 'tara': t, 'netto': n,
        'netto_bersih': bb ?? (n != null ? n - (m['potongan'] ?? 0) : null),
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nota diperbarui.')));
      }
    }
  }

  Future<void> _hapusRow(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus Nota #${m['id']}?'),
        content: Text('${m['supplier'] ?? '-'} • ${_fmt(m['netto_bersih'])} kg'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) {
      await DBHelper.delete(m['id'] as int);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(selectMode
            ? 'Terpilih: ${selected.length}'
            : 'Data Tersimpan - Review & Edit'),
        actions: [
          IconButton(
            icon: Icon(selectMode ? Icons.close : Icons.checklist),
            tooltip: selectMode ? 'Batal pilih' : 'Pilih beberapa untuk dihapus',
            onPressed: () => setState(() {
              selectMode = !selectMode;
              selected.clear();
            }),
          ),
          if (selectMode && selected.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              tooltip: 'Hapus terpilih',
              onPressed: _hapusTerpilih,
            ),
        ],
      ),
      body: rows.isEmpty
          ? const Center(child: Text('Belum ada data tersimpan.'))
          : ListView.builder(
              itemCount: rows.length,
              itemBuilder: (ctx, i) {
                final m = rows[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    onTap: selectMode
                        ? () => setState(() => selected.contains(m['id'])
                            ? selected.remove(m['id'])
                            : selected.add(m['id'] as int))
                        : null,
                    leading: selectMode
                        ? Checkbox(
                            value: selected.contains(m['id']),
                            onChanged: (v) => setState(() => v == true
                                ? selected.add(m['id'] as int)
                                : selected.remove(m['id'])),
                          )
                        : CircleAvatar(child: Text('${m['id']}')),
                    title: Text('${m['supplier'] ?? '(tanpa supplier)'}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'Tiket: ${_fmt(m['no_nota'])} • ${_fmt(m['tanggal'])} • Supir: ${m['sopir'] ?? '-'}\n'
                      'Bruto: ${_fmt(m['bruto'])} | Tara: ${_fmt(m['tara'])} | '
                      'Netto: ${_fmt(m['netto'])} kg\n'
                      'Berat bersih: ${_fmt(m['netto_bersih'])} kg ',
                    ),
                    isThreeLine: true,
                    trailing: Wrap(spacing: 4, children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editRow(m),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20,
                            color: Colors.red),
                        onPressed: () => _hapusRow(m),
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}

// ═══════════ LAYAR PANEN: input janjang per blok sebelum loading ═══════════
class PanenPage extends StatefulWidget {
  const PanenPage({super.key});
  @override
  State<PanenPage> createState() => _PanenPageState();
}

class _PanenPageState extends State<PanenPage> {
  final blok = TextEditingController();
  final jjg = TextEditingController();
  final mandor = TextEditingController();
  final ket = TextEditingController();
  late final TextEditingController tanggal;
  List<Map<String, dynamic>> rows = [];
  List<Map<String, dynamic>> notaRows = [];
  bool selectMode = false;
  final Set<int> selected = {};

  @override
  void initState() {
    super.initState();
    tanggal = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    _load();
  }

  String fmt(dynamic v) =>
      v == null ? '-' : NumberFormat('#,##0', 'id_ID').format(v);

  Future<void> _load() async {
    rows = await DBHelper.allPanen();
    notaRows = await DBHelper.all();
    if (mounted) setState(() {});
  }

  // edit data panen setelah tersimpan (blok, janjang, dll.)
  Future<void> _editPanen(Map<String, dynamic> p) async {
    final tgl = TextEditingController(text: p['tanggal']?.toString());
    final blokC = TextEditingController(text: p['blok']?.toString());
    final jjgC = TextEditingController(text: p['jjg']?.toString());
    final mandorC = TextEditingController(text: p['mandor']?.toString());
    final ketC = TextEditingController(text: p['keterangan']?.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Panen #${p['id']}'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(controller: tgl,
                decoration: const InputDecoration(labelText: 'Tanggal')),
            TextField(controller: blokC,
                decoration: const InputDecoration(labelText: 'Blok')),
            TextField(controller: jjgC, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Jml Janjang')),
            TextField(controller: mandorC,
                decoration: const InputDecoration(labelText: 'Mandor')),
            TextField(controller: ketC,
                decoration: const InputDecoration(labelText: 'Keterangan')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true) {
      final j = double.tryParse(jjgC.text);
      if (blokC.text.trim().isEmpty || j == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Blok dan Jml Janjang wajib diisi.')));
        return;
      }
      await DBHelper.updatePanen(p['id'] as int, {
        'tanggal': tgl.text,
        'blok': blokC.text.trim(),
        'jjg': j,
        'mandor': mandorC.text.trim().isEmpty ? null : mandorC.text.trim(),
        'keterangan': ketC.text.trim().isEmpty ? null : ketC.text.trim(),
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data panen diperbarui.')));
      }
    }
  }

  Future<void> _hapusTerpilih() async {
    if (selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus ${selected.length} data panen terpilih?'),
        content: const Text('Data yang dihapus tidak bisa dikembalikan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) {
      for (final id in selected) {
        await DBHelper.deletePanen(id);
      }
      setState(() { selected.clear(); selectMode = false; });
      await _load();
    }
  }

  List<int> _linkedIds(Map<String, dynamic> p) =>
      (p['tiket_ids']?.toString() ?? '')
          .split(',')
          .map((e) => int.tryParse(e.trim()))
          .whereType<int>()
          .toList();

  // label tiket terhubung untuk subtitle, contoh: "Tiket: 260921024, 260918095 (2)"
  String _tiketLabel(Map<String, dynamic> p) {
    final ids = _linkedIds(p);
    if (ids.isEmpty) return '';
    final labels = <String>[];
    for (final id in ids) {
      var label = '#$id';
      for (final n in notaRows) {
        if (n['id'] == id) {
          label = n['no_nota']?.toString() ?? label;
          break;
        }
      }
      labels.add(label);
    }
    return '\n\u2693 Tiket: ${labels.join(', ')} (${ids.length})';
  }

  // dialog pilih nota timbang yang terhubung ke blok ini (bisa beberapa)
  // - selalu membaca data panen terbaru dari DB (anti data usang)
  // - tiket yang sudah terhubung ke blok LAIN dikunci & ditandai (anti dobel)
  Future<void> _linkTiket(Map<String, dynamic> p) async {
    final allPanen = await DBHelper.allPanen();
    final cur = allPanen.firstWhere((e) => e['id'] == p['id'], orElse: () => p);
    final selected = _linkedIds(cur).toSet();

    // peta: id tiket -> nama blok lain yang sudah memakainya
    final linkedElsewhere = <int, String>{};
    for (final q in allPanen) {
      if (q['id'] == cur['id']) continue;
      final qb = q['blok']?.toString() ?? '?';
      for (final id in _linkedIds(q)) {
        linkedElsewhere[id] = qb;
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Hubungkan Tiket \u2192 Blok ${cur['blok']}'),
          content: SizedBox(
            width: double.maxFinite,
            height: 360,
            child: notaRows.isEmpty
                ? const Text('Belum ada nota timbang tersimpan.\n'
                    'Proses foto nota dulu, baru hubungkan ke blok.')
                : ListView(children: [
                    for (final n in notaRows)
                      CheckboxListTile(
                        dense: true,
                        value: selected.contains(n['id']),
                        title: Text(
                            '${n['no_nota'] ?? '-'} \u2022 ${n['nopol'] ?? '-'} \u2022 ${n['sopir'] ?? '-'}',
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                            linkedElsewhere.containsKey(n['id'])
                                ? '\u26a0 Sudah terhubung ke Blok ${linkedElsewhere[n['id']]} (hapus di blok itu dulu)'
                                : 'Berat bersih: ${fmt(n['netto_bersih'])} kg \u2022 ${n['supplier'] ?? '-'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: linkedElsewhere.containsKey(n['id'])
                                  ? Colors.orange[800]
                                  : Colors.grey[700],
                            )),
                        // tiket milik blok lain dikunci agar tidak dobel-link
                        onChanged: linkedElsewhere.containsKey(n['id'])
                            ? null
                            : (v) => setD(() {
                                  if (v == true) {
                                    selected.add(n['id'] as int);
                                  } else {
                                    selected.remove(n['id']);
                                  }
                                }),
                      ),
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await DBHelper.linkTiket(cur['id'] as int, selected.join(','));
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${selected.length} tiket dihubungkan ke Blok ${cur['blok']}.')));
      }
    }
  }

  double get totalJjg =>
      rows.fold(0.0, (a, m) => a + (m['jjg'] as num? ?? 0));

  Future<void> _simpan() async {
    final j = double.tryParse(jjg.text);
    if (blok.text.trim().isEmpty || j == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Blok dan Jumlah Janjang wajib diisi.')));
      return;
    }
    await DBHelper.insertPanen({
      'tanggal': tanggal.text,
      'blok': blok.text.trim(),
      'jjg': j,
      'mandor': mandor.text.trim().isEmpty ? null : mandor.text.trim(),
      'keterangan': ket.text.trim().isEmpty ? null : ket.text.trim(),
    });
    blok.clear();
    jjg.clear();
    ket.clear();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data panen tersimpan.')));
    }
  }

  Future<void> _hapus(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Hapus Blok ${m['blok']}?'),
        content: Text('${fmt(m['jjg'])} jjg • ${m['tanggal']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) {
      await DBHelper.deletePanen(m['id'] as int);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(selectMode
            ? 'Terpilih: ${selected.length}'
            : 'Panen - Janjang per Blok'),
        actions: [
          IconButton(
            icon: Icon(selectMode ? Icons.close : Icons.checklist),
            tooltip: selectMode ? 'Batal pilih' : 'Pilih beberapa untuk dihapus',
            onPressed: () => setState(() {
              selectMode = !selectMode;
              selected.clear();
            }),
          ),
          if (selectMode && selected.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              tooltip: 'Hapus terpilih',
              onPressed: _hapusTerpilih,
            ),
        ],
      ),
      body: Column(children: [
        // ── FORM INPUT ──
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Expanded(child: TextField(
                  controller: tanggal,
                  decoration: const InputDecoration(
                      labelText: 'Tanggal', isDense: true),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: blok,
                  decoration: const InputDecoration(
                      labelText: 'Blok *', isDense: true),
                )),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(
                  controller: jjg,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Jml Janjang *', isDense: true),
                )),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: mandor,
                  decoration: const InputDecoration(
                      labelText: 'Mandor (ops.)', isDense: true),
                )),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: ket,
                decoration: const InputDecoration(
                    labelText: 'Keterangan (ops.)', isDense: true),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _simpan,
                  icon: const Icon(Icons.add),
                  label: const Text('Simpan Panen'),
                ),
              ),
            ]),
          ),
        ),
        // ── REKAP ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            const Icon(Icons.forest, size: 18, color: Colors.green),
            const SizedBox(width: 8),
            Text('Total: ${fmt(totalJjg)} jjg dari ${rows.length} blok',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
        const Divider(),
        // ── LIST ──
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('Belum ada data panen.'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (ctx, i) {
                    final m = rows[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: ListTile(
                        dense: true,
                        onTap: selectMode
                            ? () => setState(() => selected.contains(m['id'])
                                ? selected.remove(m['id'])
                                : selected.add(m['id'] as int))
                            : null,
                        leading: selectMode
                            ? Checkbox(
                                value: selected.contains(m['id']),
                                onChanged: (v) => setState(() => v == true
                                    ? selected.add(m['id'] as int)
                                    : selected.remove(m['id'])),
                              )
                            : CircleAvatar(
                                backgroundColor: Colors.green[700],
                                foregroundColor: Colors.white,
                                child: Text('${m['jjg']}',
                                    style: const TextStyle(fontSize: 12)),
                              ),
                        title: Text('Blok ${m['blok']}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            '${m['tanggal']}${m['mandor'] != null ? ' • Mandor: ${m['mandor']}' : ''}'
                            '${_tiketLabel(m)}'
                            '${m['keterangan'] != null ? '\n${m['keterangan']}' : ''}'),
                        isThreeLine: true,
                        trailing: selectMode
                            ? null
                            : Wrap(spacing: 2, children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20,
                                      color: Colors.orange),
                                  tooltip: 'Edit data panen',
                                  onPressed: () => _editPanen(m),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.link, size: 20,
                                      color: Colors.blue),
                                  tooltip: 'Hubungkan tiket timbang',
                                  onPressed: () => _linkTiket(m),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20,
                                      color: Colors.red),
                                  tooltip: 'Hapus',
                                  onPressed: () => _hapus(m),
                                ),
                              ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
