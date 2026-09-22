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

  @override
  void initState() {
    super.initState();
    _refreshCount();
    _loadSaved();
  }

  // format ribuan Indonesia: 8460 -> "8.460"
  String fmtNum(dynamic v) =>
      v == null ? '-' : NumberFormat('#,##0', 'id_ID').format(v);

  Future<void> _loadSaved() async {
    savedRows = await DBHelper.all();
    if (mounted) setState(() {});
  }

  Future<void> _refreshCount() async {
    final c = await DBHelper.count();
    setState(() => savedCount = c);
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
        n.bruto = double.tryParse(bruto.text);
        n.tara = double.tryParse(tara.text);
        n.netto = double.tryParse(netto.text);
        n.jjg = double.tryParse(jjg.text);
        n.catatan = n.perluCek ? 'CEK MANUAL' : '';
      });
    }
  }

  // BUKA LAYAR REVIEW DATA TERSIMPAN
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
          Text('Rekap Tersimpan: $savedCount nota',
              style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _editRow(Map<String, dynamic> m) async {
    final supplier = TextEditingController(text: m['supplier']?.toString());
    final noNota = TextEditingController(text: m['no_nota']?.toString());
    final bruto = TextEditingController(text: m['bruto']?.toString());
    final tara = TextEditingController(text: m['tara']?.toString());
    final netto = TextEditingController(text: m['netto']?.toString());
    final berat = TextEditingController(text: m['netto_bersih']?.toString());
    final harga = TextEditingController(text: m['harga']?.toString());
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
            TextField(controller: bruto, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Bruto (kg)')),
            TextField(controller: tara, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tara (kg)')),
            TextField(controller: netto, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Netto (kg)')),
            TextField(controller: berat, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Berat Bersih (kg)')),
            TextField(controller: harga, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga/kg')),
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
      final h = double.tryParse(harga.text);
      await DBHelper.update(m['id'] as int, {
        'supplier': supplier.text.isEmpty ? null : supplier.text,
        'no_nota': noNota.text,
        'bruto': b, 'tara': t, 'netto': n,
        'netto_bersih': bb ?? (n != null ? n - (m['potongan'] ?? 0) : null),
        'harga': h,
        'total': (bb != null && h != null) ? bb * h : null,
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
      appBar: AppBar(title: const Text('Data Tersimpan - Review & Edit')),
      body: rows.isEmpty
          ? const Center(child: Text('Belum ada data tersimpan.'))
          : ListView.builder(
              itemCount: rows.length,
              itemBuilder: (ctx, i) {
                final m = rows[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${m['id']}')),
                    title: Text('${m['supplier'] ?? '(tanpa supplier)'}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'Tiket: ${_fmt(m['no_nota'])} • ${_fmt(m['tanggal'])}\n'
                      'Bruto: ${_fmt(m['bruto'])} | Tara: ${_fmt(m['tara'])} | '
                      'Netto: ${_fmt(m['netto'])} kg\n'
                      'Berat bersih: ${_fmt(m['netto_bersih'])} kg • '
                      'Harga: ${_fmt(m['harga'])} • Total: ${_fmt(m['total'])}',
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
    if (mounted) setState(() {});
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
      appBar: AppBar(title: const Text('Panen - Janjang per Blok')),
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
                        leading: CircleAvatar(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          child: Text('${m['jjg']}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                        title: Text('Blok ${m['blok']}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            '${m['tanggal']}${m['mandor'] != null ? ' • Mandor: ${m['mandor']}' : ''}'
                            '${m['keterangan'] != null ? '\n${m['keterangan']}' : ''}'),
                        isThreeLine: m['keterangan'] != null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, size: 20,
                              color: Colors.red),
                          onPressed: () => _hapus(m),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
