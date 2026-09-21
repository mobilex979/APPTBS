// Aplikasi Nota Timbang TBS - layar utama
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'db_helper.dart';
import 'excel_exporter.dart';
import 'nota_parser.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Nota Timbang TBS',
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

  @override
  void initState() {
    super.initState();
    DBHelper.count().then((c) => setState(() => savedCount = c));
  }

  Future<String> _ocr(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final res = await recognizer.processImage(InputImage.fromFilePath(path));
      return res.text;
    } finally {
      recognizer.close();
    }
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
    final c = await DBHelper.count();
    setState(() {
      draft.clear();
      savedCount = c;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Semua nota tersimpan.')));
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
    await ExcelExporter.exportAndShare(rows, tgl);
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
                decoration: const InputDecoration(labelText: 'No Nota')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nota Timbang TBS'),
          actions: [Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: Text('Tersimpan: $savedCount')),
          )]),
      body: loading
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Membaca nota...'),
            ]))
          : draft.isEmpty
              ? const Center(child: Text(
                  'Ambil foto nota atau pilih banyak foto dari galeri.',
                  textAlign: TextAlign.center))
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
