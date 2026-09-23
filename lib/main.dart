// Aplikasi Buslin Bross - Nota Timbang TBS (layar utama)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;
import 'db_helper.dart';
import 'license.dart';
import 'excel_exporter.dart';
import 'nota_parser.dart';

void main() => runApp(const MyApp());

// ============================================================
// PILIH TEMA TAMPILAN — cukup ganti angka PILIH_TEMA: 1 / 2 / 3 / 4
//   1 = Hijau Sawit     : terang, klasik, seperti sekarang
//   2 = Hijau Tua       : elegan/premium, AppBar hijau tua
//   3 = Biru Profesional: netral formal, cocok untuk kantor
//   4 = Dark Mode       : gelap, nyaman dipakai malam hari
// ============================================================
const int PILIH_TEMA = 1;

ThemeData temaAplikasi(int pilihan) {
  switch (pilihan) {
    case 2: // Hijau Tua Elegan
      return ThemeData(
        colorSchemeSeed: const Color(0xFF1B5E20),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1B5E20),
          foregroundColor: Colors.white,
        ),
      );
    case 3: // Biru Profesional
      return ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF283593),
          foregroundColor: Colors.white,
        ),
      );
    case 4: // Dark Mode
      return ThemeData(
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
        useMaterial3: true,
      );
    default: // 1 = Hijau Sawit
      return ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true);
  }
}

// tanggal: ISO (YYYY-MM-DD) <-> tampilan (DD-MM-YYYY)
String isoKeTampilan(String? iso) {
  if (iso == null || iso.length < 10) return iso ?? '';
  return '${iso.substring(8, 10)}-${iso.substring(5, 7)}-${iso.substring(0, 4)}';
}

String? tampilanKeIso(String t) {
  final p = t.trim().split('-');
  if (p.length == 3) {
    return '${p[2]}-${p[1].padLeft(2, '0')}-${p[0].padLeft(2, '0')}';
  }
  return t.trim().isEmpty ? null : t.trim();
}

// '2026-09' -> 'September 2026'
String namaBulan(String ym) {
  const bln = ['Januari','Februari','Maret','April','Mei','Juni','Juli',
      'Agustus','September','Oktober','November','Desember'];
  final p = ym.split('-');
  if (p.length != 2) return ym;
  final b = int.tryParse(p[1]);
  return '${b != null && b >= 1 && b <= 12 ? bln[b - 1] : p[1]} ${p[0]}';
}

// Field dengan SARAN OTOMATIS dari riwayat (Opsi A) + huruf otomatis KAPITAL
Widget saranField({
  required String label,
  required TextEditingController ctrl,
  required String kolom,
}) {
  return FutureBuilder<List<String>>(
    future: DBHelper.saran(kolom),
    builder: (context, snap) {
      final opts = snap.data ?? const <String>[];
      return Autocomplete<String>(
        optionsBuilder: (tv) {
          final q = tv.text.trim().toUpperCase();
          return opts
              .where((o) => q.isEmpty || o.toUpperCase().contains(q))
              .toList();
        },
        fieldViewBuilder: (context, fc, fn, onFieldSubmitted) {
          if (fc.text != ctrl.text) fc.text = ctrl.text;
          return TextField(
            controller: fc,
            focusNode: fn,
            textCapitalization: TextCapitalization.characters,
            onChanged: (v) => ctrl.text = v,
            decoration: InputDecoration(labelText: label),
          );
        },
        onSelected: (v) => ctrl.text = v,
        optionsMaxHeight: 180,
      );
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BUSLIN BROS - Aplikasi Tbs',
        theme: temaAplikasi(PILIH_TEMA),
        home: const Gate(),
        debugShowCheckedModeBanner: false,
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
  bool kunciBulanan = false;
  StreamSubscription<List<SharedMediaFile>>? _subShare;
  int savedCount = 0;
  List<Map<String, dynamic>> savedRows = [];
  List<Map<String, dynamic>> panenRows = [];

  @override
  void initState() {
    super.initState();
    _refreshCount();
    _loadSaved();
    _cekKunci();
    // buka file backup langsung dari WA / file manager (Versi 2)
    if (!VERSI_HAPUS_OTOMATIS) {
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        final path = files.isNotEmpty ? files.first.path : null;
        if (path != null) _restoreDariPath(path);
      });
      _subShare =
          ReceiveSharingIntent.instance.getMediaStream().listen((files) {
        final path = files.isNotEmpty ? files.first.path : null;
        if (path != null) _restoreDariPath(path);
      });
    }
  }

  @override
  void dispose() {
    _subShare?.cancel();
    super.dispose();
  }

  Future<void> _cekKunci() async {
    final k = await TutupBuku.perluKunci();
    if (mounted) setState(() => kunciBulanan = k);
  }

  // format ribuan Indonesia: 8460 -> "8.460"
  String fmtNum(dynamic v) =>
      v == null ? '-' : NumberFormat('#,##0', 'id_ID').format(v);

  Future<void> _loadSaved() => _refreshCount();

  Future<void> _refreshCount() async {
    var all = await DBHelper.all();
    var pAll = await DBHelper.allPanen();
    if (!VERSI_HAPUS_OTOMATIS && SesiBulan.bulanDipilih != null) {
      final bl = SesiBulan.bulanDipilih!;
      bool cocok(Map<String, dynamic> m) =>
          (m['tanggal'] ?? m['created_at'] ?? '')
              .toString()
              .startsWith(bl);
      all = all.where(cocok).toList();
      pAll = pAll.where(cocok).toList();
    }
    savedRows = all;
    panenRows = pAll;
    if (mounted) setState(() => savedCount = all.length);
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
    final sudahTersimpan = await DBHelper.noTiketTersimpan();
    for (final f in files) {
      final text = await _ocr(f.path);
      final n = NotaParser.parse(text, f.name);
      // screening anti-double: cek ke database & antrian foto batch ini
      n.sudahAda = n.noNota != null &&
          (sudahTersimpan.contains(n.noNota!) ||
              draft.any((d) => d.noNota == n.noNota));
      setState(() => draft.add(n));
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
    var dilewati = 0;
    for (final n in draft) {
      if (n.sudahAda) {
        dilewati++;          // no tiket double -> tidak disimpan
        continue;
      }
      await DBHelper.insert(n);
    }
    setState(() => draft.clear());
    await _refreshCount();
    await _loadSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(dilewati > 0
              ? 'Tersimpan. $dilewati nota double (no tiket sama) dilewati.'
              : 'Semua nota tersimpan.')));
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
        if (f is File &&
            f.path.contains('Nota_Timbang_') &&
            (f.path.endsWith('.xlsx') || f.path.toLowerCase().endsWith('.zip'))) {
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
        text: isoKeTampilan(DateFormat('yyyy-MM-dd').format(DateTime.now())));
    final noNota = TextEditingController();
    final perusahaan = TextEditingController();
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
                decoration: const InputDecoration(labelText: 'Tanggal (DD-MM-YYYY)')),
            TextField(controller: noNota,
                decoration: const InputDecoration(labelText: 'No Tiket')),
            saranField(
                label: 'Perusahaan/PKS',
                ctrl: perusahaan,
                kolom: 'perusahaan'),
            saranField(
                label: 'Supplier / Relasi',
                ctrl: supplier,
                kolom: 'supplier'),
            saranField(label: 'Plat No', ctrl: nopol, kolom: 'nopol'),
            saranField(label: 'Nama Supir', ctrl: sopir, kolom: 'sopir'),
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
        ..tanggal = tampilanKeIso(tgl.text)
        ..noNota = noNota.text.trim().isEmpty ? null : noNota.text.trim()
        ..perusahaan = perusahaan.text.trim().isEmpty ? null : perusahaan.text.trim()
        ..supplier = supplier.text.trim().isEmpty ? null : supplier.text.trim()
        ..nopol = NotaParser.normPlat(nopol.text)
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
    final mandor = await Profil.namaMandor();
    await ExcelExporter.exportAndShare(rows, tgl, panen: panen, mandor: mandor);
        final hapusInfo = await TutupBuku.tandaiBackup();

    await _cekKunci();
    await _refreshCount();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(hapusInfo != null
              ? 'Export OK. $hapusInfo.'
              : 'Export OK. Input terbuka kembali.')));
    }
  }

  Future<void> _edit(Nota n) async {
    final perusahaan = TextEditingController(text: n.perusahaan);
    final tgl = TextEditingController(text: isoKeTampilan(n.tanggal));
    final supplier = TextEditingController(text: n.supplier);
    final bruto = TextEditingController(text: n.bruto?.toString() ?? '');
    final tara = TextEditingController(text: n.tara?.toString() ?? '');
    final netto = TextEditingController(text: n.netto?.toString() ?? '');
    final potongan = TextEditingController(text: n.potongan?.toString() ?? '');
    final noNota = TextEditingController(text: n.noNota);
    final nopol = TextEditingController(text: n.nopol);
    final sopir = TextEditingController(text: n.sopir);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cek / Edit Nota'),
        content: SingleChildScrollView(
          child: Column(children: [
            TextField(controller: tgl,
                decoration: const InputDecoration(labelText: 'Tanggal (DD-MM-YYYY)')),
            saranField(
                label: 'Perusahaan/PKS',
                ctrl: perusahaan,
                kolom: 'perusahaan'),
            saranField(label: 'Supplier', ctrl: supplier, kolom: 'supplier'),
            TextField(controller: noNota,
                decoration: const InputDecoration(labelText: 'No Tiket')),
            saranField(label: 'Nomor Polisi', ctrl: nopol, kolom: 'nopol'),
            saranField(label: 'Nama Supir', ctrl: sopir, kolom: 'sopir'),
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
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        n.tanggal = tampilanKeIso(tgl.text);
        n.perusahaan = perusahaan.text.isEmpty ? null : perusahaan.text;
        n.supplier = supplier.text.isEmpty ? null : supplier.text;
        n.noNota = noNota.text;
        n.nopol = NotaParser.normPlat(nopol.text);
        n.sopir = sopir.text.isEmpty ? null : sopir.text;
        n.bruto = double.tryParse(bruto.text);
        n.tara = double.tryParse(tara.text);
        n.netto = double.tryParse(netto.text);
        n.potongan = double.tryParse(potongan.text);
        n.catatan = n.perluCek ? 'CEK MANUAL' : '';
      });
    }
  }

  // INPUT MANUAL (NEW): ketik data timbang tanpa kamera/galeri
  
  // BACKUP seluruh data -> file TERENKRIPSI (.bbos) -> share ke WA/email
  Future<void> _backup() async {
    try {
      final data = await DBHelper.backupAll();
      final dir = await getExternalStorageDirectory()
          ?? await getApplicationDocumentsDirectory();
      final tgl = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final f = File('${dir.path}/backup_buslin_$tgl.bbos');
      await f.writeAsString(enkripBackup(jsonEncode(data)), flush: true);
      await Share.shareXFiles([XFile(f.path)],
          text: 'Backup data BUSLIN BROS ($tgl) - file terkunci, hanya bisa dibuka owner.');
      if (VERSI_HAPUS_OTOMATIS) {
        final hapusInfo = await TutupBuku.tandaiBackup();
        await _cekKunci();
        await _refreshCount();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(hapusInfo != null
                  ? 'Backup terkirim. $hapusInfo.'
                  : 'Backup terkirim. Input terbuka kembali.')));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Backup gagal: $e')));
    }
  }

  // RESTORE: pilih file -> restore pintar (gabung/timpa/konflik)
  Future<void> _restore() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['bbos', 'json']);
    final path = res?.files.single.path;
    if (path != null) await _restoreDariPath(path);
  }

  // restore dari path file (dipakai file picker & buka-langsung-dari-WA)
  Future<void> _restoreDariPath(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Backup?'),
        content: Text('File: ${path.split('/').last}\n'
            'Tiket baru ditambah, tiket sama (berat sama) ditimpa otomatis.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final raw = await File(path).readAsString();
      var jsonStr = dekripBackup(raw);
      jsonStr ??= raw;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final hasil = await DBHelper.restoreAll(data);
      await _refreshCount();
      final k = (hasil['konflik'] as List<Map<String, dynamic>>?) ?? [];
      if (k.isNotEmpty && mounted) {
        await _konflikDialog(k);
        await _refreshCount();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Restore selesai: +${hasil['tambah']} tiket, timpa ${hasil['timpa']}'
                '${k.isNotEmpty ? ', konflik ${k.length} sesuai pilihan' : ''}.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Restore gagal: file bukan backup valid / rusak.')));
      }
    }
  }

  // dialog penyelesaian konflik berat bersih
  Future<void> _konflikDialog(List<Map<String, dynamic>> konflik) async {
    final pilih = List<bool>.filled(konflik.length, false);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('⚠ KONFLIK - ${konflik.length} TIKET'),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView(children: [
              for (var i = 0; i < konflik.length; i++)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tiket ${konflik[i]['backup']['no_nota']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                              'Tersimpan: ${fmtNum(konflik[i]['lama']['netto_bersih'])} kg'
                              '  vs  Backup: ${fmtNum(konflik[i]['backup']['netto_bersih'])} kg'),
                          Row(children: [
                            Expanded(
                              child: RadioListTile<bool>(
                                dense: true,
                                value: false,
                                groupValue: pilih[i],
                                onChanged: (v) => setD(() => pilih[i] = false),
                                title: const Text('Tersimpan',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<bool>(
                                dense: true,
                                value: true,
                                groupValue: pilih[i],
                                onChanged: (v) => setD(() => pilih[i] = true),
                                title: const Text('Backup',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          ]),
                        ]),
                  ),
                ),
            ]),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('TERAPKAN & RESTORE')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await DBHelper.selesaikanKonflik(konflik, pilih);
    }
  }

  // ── LAYAR KUNCI (tutup buku tiap Senin) ──
  Widget _layarKunci() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_clock, size: 72, color: Colors.orange),
          const SizedBox(height: 12),
          Text('TUTUP BUKU - HARI SENIN',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800])),
          const SizedBox(height: 12),
          const Text(
              'Semua fitur input DIKUNCI sampai backup dikirim ke owner.',
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            VERSI_HAPUS_OTOMATIS
                ? 'Setelah backup terkirim: input terbuka. Data bulan lalu TERHAPUS otomatis setiap tanggal 1.'
                : 'Setelah export/backup: input terbuka kembali.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed:
                  VERSI_HAPUS_OTOMATIS ? _backup : _exportExcel,
              icon: const Icon(Icons.table_chart),
              label: Text(VERSI_HAPUS_OTOMATIS
                  ? 'KIRIM BACKUP SEKARANG'
                  : 'EXPORT TO EXCEL SEKARANG'),
            ),
          ),
        ]),
      ),
    );
  }

  // ── RIWAYAT BULAN (Versi 2) ──
  Future<void> _riwayat() async {
    if (VERSI_HAPUS_OTOMATIS) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Versi ini tidak punya riwayat (data bulan lalu dihapus otomatis).')));
      return;
    }
    if (!SesiBulan.riwayatTerbuka) {
      final ok = await _mintaKodeRiwayat();
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Kode salah.')));
        }
        return;
      }
      SesiBulan.riwayatTerbuka = true;
    }
    final daftar = await DBHelper.bulanBulanAda();
    final sekarang = DateFormat('yyyy-MM').format(DateTime.now());
    final bulan = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih Bulan'),
        children: [
          for (final b in daftar)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, b),
              child: Row(children: [
                Icon(b == sekarang ? Icons.location_on : Icons.history,
                    size: 18,
                    color: b == sekarang ? Colors.green : Colors.grey),
                const SizedBox(width: 8),
                Text(namaBulan(b),
                    style: TextStyle(
                        fontWeight:
                            b == sekarang ? FontWeight.bold : FontWeight.normal)),
              ]),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'RESET'),
            child: const Text('← Kembali ke bulan berjalan',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (bulan == 'RESET') {
      SesiBulan.bulanDipilih = null;
    } else if (bulan != null) {
      SesiBulan.bulanDipilih = bulan;
    }
    await _refreshCount();
  }

  Future<bool> _mintaKodeRiwayat() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AKSES RIWAYAT'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Kode supervisor'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Buka')),
        ],
      ),
    );
    return ok == true && ctrl.text.trim() == KODE_RIWAYAT;
  }

  // GANTI NAMA MANDOR HP INI
  Future<void> _profilMandor() async {
    final sekarang = await Profil.namaMandor();
    final ctrl = TextEditingController(text: sekarang);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Profil Mandor HP Ini'),
        content: TextField(
          controller: ctrl,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              labelText: 'Nama mandor penanggung jawab'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().length >= 2) {
      await Profil.simpanMandor(ctrl.text);
      await _refreshCount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nama mandor diperbarui. Data berikutnya '
                'memakai nama ini.')));
      }
    }
  }

  // BUKA LAYAR PANEN + refresh home saat kembali
  Future<void> _bukaPanen() async {
    if (kunciBulanan) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('\ud83d\udd12 Input Dikunci'),
          content: const Text(
              'Tutup buku bulanan: export dulu sebelum input panen.'),
          actions: [
            FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _exportExcel();
                },
                child: const Text('Export Sekarang')),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Nanti')),
          ],
        ),
      );
      return;
    }
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const PanenPage()));
    await _refreshCount();   // update Total jjg & Avg kg/JJG di home
  }

  Future<void> _bukaDataTersimpan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SavedPage()),
    );
    await _refreshCount();
    await _loadSaved();
  }

  Widget _isiTabel() {
    return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SingleChildScrollView(
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.green[50]),
        columns: const [
          DataColumn(label: Text('No Tiket')),
          DataColumn(label: Text('Tanggal')),
          DataColumn(label: Text('Plat No')),
          DataColumn(label: Text('Perusahaan')),
          DataColumn(label: Text('Supir')),
          DataColumn(label: Text('Bruto'), numeric: true),
          DataColumn(label: Text('Tarra'), numeric: true),
          DataColumn(label: Text('Potongan'), numeric: true),
          DataColumn(label: Text('Berat Bersih'), numeric: true),
        ],
        rows: [
          for (final m in savedRows)
            DataRow(cells: [
              DataCell(SelectableText(m['no_nota']?.toString() ?? '-')),
              DataCell(SelectableText(() {
                final t = m['tanggal']?.toString();
                return (t != null && t.contains('-'))
                    ? t.split('-').reversed.join('-')
                    : (t ?? '-');
              }())),
              DataCell(SelectableText(m['nopol']?.toString() ?? '-')),
              DataCell(SelectableText(m['perusahaan']?.toString() ?? '-')),
              DataCell(SelectableText(m['sopir']?.toString() ?? '-')),
              DataCell(SelectableText(fmtNum(m['bruto']))),
              DataCell(SelectableText(fmtNum(m['tara']))),
              DataCell(SelectableText(fmtNum(m['potongan']))),
              DataCell(SelectableText(fmtNum(m['netto_bersih']),
                  style: const TextStyle(fontWeight: FontWeight.bold))),
            ]),
        ],
      ),
    ),
    );
  }
  // TABEL REKAP DATA TERSIMPAN di halaman utama
  Widget _buildRekap() {
    if (!VERSI_HAPUS_OTOMATIS && SesiBulan.bulanDipilih != null) {
      return Column(children: [
        Container(
          width: double.infinity,
          color: Colors.amber[100],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            const Icon(Icons.history, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Mode riwayat: ${namaBulan(SesiBulan.bulanDipilih!)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () {
                SesiBulan.bulanDipilih = null;
                _refreshCount();
              },
              child: const Text('← Bulan ini'),
            ),
          ]),
        ),
        const Divider(),
        Expanded(
          child: savedRows.isEmpty
              ? const Center(child: Text('Tidak ada data pada bulan ini.'))
              : _isiTabel(),
        ),
      ]);
    }
    if (savedRows.isEmpty) {
      return const Center(child: Text(
          'Belum ada data. Ambil foto nota atau pilih banyak foto dari galeri.',
          textAlign: TextAlign.center));
    }
    return Column(children: [
      () {
        final totBerat = savedRows.fold<double>(
            0, (a, m) => a + (m['netto_bersih'] as num? ?? 0));
        final totJjg =
            panenRows.fold<double>(0, (a, m) => a + (m['jjg'] as num? ?? 0));
        final avg = totJjg > 0 ? totBerat / totJjg : null;
        // rata-rata kg/JJG dipisah per BLOK
        final beratOf = <int, double>{};
        for (final n in savedRows) {
          beratOf[n['id'] as int] = (n['netto_bersih'] as num? ?? 0).toDouble();
        }
        final blokBerat = <String, double>{};
        final blokJjg = <String, double>{};
        for (final p in panenRows) {
          final bk = (p['blok']?.toString().trim().isNotEmpty == true)
              ? p['blok'].toString()
              : '(tanpa blok)';
          var b = 0.0;
          for (final tid in (p['tiket_ids']?.toString() ?? '').split(',')) {
            final id = int.tryParse(tid.trim());
            if (id != null && beratOf.containsKey(id)) b += beratOf[id]!;
          }
          blokBerat[bk] = (blokBerat[bk] ?? 0.0) + b;
          blokJjg[bk] = (blokJjg[bk] ?? 0.0) + ((p['jjg'] as num?) ?? 0).toDouble();
        }
        final avgBlok = blokJjg.entries
            .where((e) => e.value > 0 && (blokBerat[e.key] ?? 0) > 0)
            .map((e) =>
                '${e.key}: ${(blokBerat[e.key]! / e.value).toStringAsFixed(1)}')
            .join(' \u2022 ');
        final ringkasan = 'Rekap Tersimpan: $savedCount nota\n'
            'Total: ${fmtNum(totBerat)} kg \u2022 Panen ${fmtNum(totJjg)} jjg \u2022 Avg: ${avg != null ? avg.toStringAsFixed(1) : '-'} kg/JJG'
            '${avgBlok.isNotEmpty ? '\nPer blok: $avgBlok kg/JJG' : ''}';
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          color: Colors.green[50],
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              const Icon(Icons.table_chart, size: 26, color: Colors.green),
              const SizedBox(width: 10),
              Expanded(
                child:
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SelectableText('Rekap Tersimpan: $savedCount nota',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 17)),
                  SelectableText(ringkasan.split('\n').sublist(1).join('\n'),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 20, color: Colors.green),
                tooltip: 'Salin rekap ke clipboard',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: ringkasan));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Rekap tersalin. Tempel di WA/email.')));
                },
              ),
            ]),
          ),
        );
      }(),
      const Divider(),
        Expanded(child: _isiTabel()),
    const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Klik "Tersimpan" di atas untuk review & edit detail',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (kunciBulanan) {
      return Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BUSLIN BROS',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Aplikasi Tbs',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.normal)),
            ],
          ),
        ),
        body: _layarKunci(),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BUSLIN BROS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Aplikasi Tbs',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.normal)),
            Text("by YY's",
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          // TERSIMPAN (bold) = tombol buka data tersimpan
          InkWell(
            onTap: _bukaDataTersimpan,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text('Tersimpan: $savedCount',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          // MENU TITIK TIGA (semua aksi)
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (v) {
              switch (v) {
                case 'panen':
                  _bukaPanen();
                  break;
                case 'mandor':
                  _profilMandor();
                  break;
                case 'riwayat':
                  _riwayat();
                  break;
                case 'export':
                  _exportExcel();
                  break;
                case 'backup':
                  _backup();
                  break;
                case 'restore':
                  _restore();
                  break;
                case 'hapus':
                  _hapusSemua();
                  break;
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                  value: 'panen',
                  child: Text('\ud83c\udf34 Panen - Janjang per Blok')),
              PopupMenuItem(
                  value: 'mandor',
                  child: Text('\ud83d\udc64 Ganti Mandor')),
              if (!VERSI_HAPUS_OTOMATIS)
                const PopupMenuItem(
                    value: 'riwayat',
                    child:
                        Text('\ud83d\udd13 Lihat Data Bulan Sebelumnya')),
              PopupMenuDivider(),
              if (!VERSI_HAPUS_OTOMATIS)
                const PopupMenuItem(
                    value: 'export',
                    child: Text('\ud83d\udcca Export to Excel')),
              PopupMenuItem(
                  value: 'backup', child: Text('\ud83d\udcbe Backup Data')),
              PopupMenuItem(
                  value: 'restore',
                  child: Text('\ud83d\udce5 Restore Data')),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'hapus',
                child: Text('\ud83d\uddd1\ufe0f Delete All',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: loading
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
                      color: n.sudahAda
                          ? Colors.orange[50]
                          : (n.perluCek ? Colors.red[50] : null),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text(
                            '${n.supplier ?? '(supplier kosong)'}${n.sudahAda ? '  \u26a0 SUDAH ADA' : ''}'),
                        subtitle: SelectableText(
                          'Nota: ${n.noNota ?? '-'} | '
                          'Bruto: ${n.bruto ?? '-'} | Tara: ${n.tara ?? '-'} | '
                          'Netto: ${n.netto ?? '-'} kg',
                        ),
                        trailing: Wrap(spacing: 4, children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _edit(n),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete,
                                size: 20, color: Colors.red),
                            tooltip: 'Buang dari daftar',
                            onPressed: () => setState(() => draft.remove(n)),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      bottomNavigationBar: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
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
            Expanded(child: FilledButton.tonalIcon(
                onPressed: _inputManual,
                icon: const Icon(Icons.edit_note),
                label: const Text('Input Manual'))),
          ]),
            ]),
          ),
        ),
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
    final perusahaan = TextEditingController(text: m['perusahaan']?.toString());
    final supplier = TextEditingController(text: m['supplier']?.toString());
    final noNota = TextEditingController(text: m['no_nota']?.toString());
    final nopol = TextEditingController(text: m['nopol']?.toString());
    final sopir = TextEditingController(text: m['sopir']?.toString());
    final bruto = TextEditingController(text: m['bruto']?.toString());
    final tara = TextEditingController(text: m['tara']?.toString());
    final netto = TextEditingController(text: m['netto']?.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Nota #${m['id']}'),
        content: SingleChildScrollView(
          child: Column(children: [
            saranField(
                label: 'Perusahaan/PKS',
                ctrl: perusahaan,
                kolom: 'perusahaan'),
            saranField(label: 'Supplier', ctrl: supplier, kolom: 'supplier'),
            TextField(controller: noNota,
                decoration: const InputDecoration(labelText: 'No Tiket')),
            saranField(label: 'Nomor Polisi', ctrl: nopol, kolom: 'nopol'),
            saranField(label: 'Nama Supir', ctrl: sopir, kolom: 'sopir'),
            TextField(controller: bruto, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Bruto (kg)')),
            TextField(controller: tara, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Tara (kg)')),
            TextField(controller: netto, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Netto (kg)')),
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
      await DBHelper.update(m['id'] as int, {
        'perusahaan': perusahaan.text.isEmpty ? null : perusahaan.text,
        'supplier': supplier.text.isEmpty ? null : supplier.text,
        'no_nota': noNota.text,
        'nopol': NotaParser.normPlat(nopol.text),
        'sopir': sopir.text.isEmpty ? null : sopir.text,
        'bruto': b, 'tara': t, 'netto': n,
        'netto_bersih':
            (n != null) ? n - ((m['potongan'] as num? ?? 0)) : null,
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: rows.isEmpty
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
                    title: SelectableText('${m['supplier'] ?? '(tanpa supplier)'}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: SelectableText(
                      '${m['perusahaan'] ?? '-'} • Tiket: ${_fmt(m['no_nota'])} • ${_fmt(m['tanggal'])} • Supir: ${m['sopir'] ?? '-'}\n'
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
    Profil.namaMandor().then((m) {
      if (m != null) mandor.text = m;
    });
    _load();
  }

  String fmt(dynamic v) =>
      v == null ? '-' : NumberFormat('#,##0', 'id_ID').format(v);

  Future<void> _load() async {
    var r = await DBHelper.allPanen();
    var n = await DBHelper.all();
    if (!VERSI_HAPUS_OTOMATIS && SesiBulan.bulanDipilih != null) {
      final bl = SesiBulan.bulanDipilih!;
      bool cocok(Map<String, dynamic> m) =>
          (m['tanggal'] ?? m['created_at'] ?? '').toString().startsWith(bl);
      r = r.where(cocok).toList();
      n = n.where(cocok).toList();
    }
    rows = r;
    notaRows = n;
    if (mounted) setState(() {});
  }

  // edit data panen setelah tersimpan (blok, janjang, dll.)
  Future<void> _editPanen(Map<String, dynamic> p) async {
    final tgl = TextEditingController(text: isoKeTampilan(p['tanggal']?.toString()));
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
        'tanggal': tampilanKeIso(tgl.text),
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

  // rata-rata kg/JJG blok ini = total berat tiket terhubung / jjg blok
  double? _avgBlok(Map<String, dynamic> p) {
    final jjg = (p['jjg'] as num?) ?? 0;
    if (jjg <= 0) return null;
    var berat = 0.0;
    for (final id in _linkedIds(p)) {
      for (final n in notaRows) {
        if (n['id'] == id) {
          berat += (n['netto_bersih'] as num? ?? 0);
          break;
        }
      }
    }
    return berat > 0 ? berat / jjg : null;
  }

  String _avgLabel(Map<String, dynamic> p) {
    final a = _avgBlok(p);
    return a == null ? '' : '\nRata2: ${a.toStringAsFixed(1)} kg/JJG';
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
                        subtitle: SelectableText(
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
      'mandor': await Profil.namaMandor() ??
          (mandor.text.trim().isEmpty ? null : mandor.text.trim()),
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
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(children: [
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
                  textCapitalization: TextCapitalization.characters,
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
                  readOnly: true,
                  decoration: const InputDecoration(
                      labelText: 'Mandor (terkunci HP ini)', isDense: true),
                )),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: ket,
                textCapitalization: TextCapitalization.characters,
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
                        title: SelectableText('Blok ${m['blok']}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: SelectableText(
                            '${m['tanggal']}${m['mandor'] != null ? ' • Mandor: ${m['mandor']}' : ''}'
                            '${_tiketLabel(m)}'
                            '${_avgLabel(m)}'
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
        ),
    );
  }
}

// ═══════════ PINTU GERBANG: cek lisensi sebelum masuk aplikasi ═══════════
class Gate extends StatelessWidget {
  const Gate({super.key});

  static Future<int> _status() async {
    if (!await License.sudahAktif()) return 1;   // perlu aktivasi lisensi
    if (await Profil.namaMandor() == null) return 2; // perlu nama mandor
    return 3;                                    // lolos
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
        future: _status(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          switch (snap.data!) {
            case 1:
              return const LicensePage();
            case 2:
              return const MandorPage();
            default:
              return const HomePage();
          }
        },
      );
}

// ═══════════ LAYAR AKTIVASI LISENSI ═══════════
class LicensePage extends StatefulWidget {
  const LicensePage({super.key});
  @override
  State<LicensePage> createState() => _LicensePageState();
}

class _LicensePageState extends State<LicensePage> {
  final kode = TextEditingController();
  String? pesan;
  String kodeHp = '...';

  @override
  void initState() {
    super.initState();
    License.kodeHP().then((v) => setState(() => kodeHp = v));
  }

  Future<void> _aktivasi() async {
    final exp = await License.cek(kode.text);
    if (exp == null) {
      setState(() => pesan = 'Kode salah. Hubungi pemilik aplikasi.');
      return;
    }
    await License.simpan(kode.text);
    if (mounted) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.verified_user, size: 72, color: Colors.green),
            const SizedBox(height: 12),
            const Text('BUSLIN BROS',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const Text('Aplikasi Tbs',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 24),
            const Text('Kirim Kode HP di bawah ini ke pemilik aplikasi,\n'
                'lalu masukkan kode aktivasi yang Anda terima:',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.phone_android, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('KODE HP INI',
                            style: TextStyle(
                                fontSize: 11, color: Colors.black54)),
                        SelectableText(kodeHp,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18)),
                      ]),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Salin Kode HP',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: kodeHp));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kode HP tersalin.')));
                  },
                ),
              ]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: kode,
              keyboardType: TextInputType.number,
              maxLength: 10,
              decoration: const InputDecoration(
                labelText: 'Kode lisensi (10 digit)',
                border: OutlineInputBorder(),
              ),
            ),
            if (pesan != null)
              Text(pesan!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _aktivasi,
                icon: const Icon(Icons.key),
                label: const Text('Aktivasi'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════ SETUP MANDOR — HP dikunci untuk 1 mandor ═══════════
class MandorPage extends StatefulWidget {
  const MandorPage({super.key});
  @override
  State<MandorPage> createState() => _MandorPageState();
}

class _MandorPageState extends State<MandorPage> {
  final nama = TextEditingController();

  Future<void> _simpan() async {
    if (nama.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nama mandor minimal 2 huruf.')));
      return;
    }
    await Profil.simpanMandor(nama.text);
    if (mounted) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person_pin, size: 72, color: Colors.green),
            const SizedBox(height: 12),
            const Text('BUSLIN BROS',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            const Text(
                'HP ini dikunci untuk SATU mandor penanggung jawab.\n'
                'Semua data panen & export akan bertanda nama mandor ini.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextField(
              controller: nama,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Nama Mandor / Penanggung Jawab',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _simpan,
                icon: const Icon(Icons.save),
                label: const Text('Simpan & Masuk'),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Nama bisa diganti lewat icon orang di halaman utama '
                'jika mandor berganti.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }
}
