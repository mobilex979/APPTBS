# Susunan Pembuatan Aplikasi Android Nota Timbang TBS
## (Flutter + Google ML Kit + SQLite + Export Excel)

Aplikasi: foto nota timbang (kamera/galeri) → OCR offline → verifikasi →
simpan per supplier per hari → export Excel per supplier.

Urutan tahap sengaja disusun agar tiap tahap bisa diuji sendiri
sebelum lanjut ke tahap berikutnya.

---

## TAHAP 0 — Persiapan (± 1 hari)
1. Install **Flutter SDK** stabil → https://docs.flutter.dev/get-started/install
2. Install **Android Studio** + SDK Android (min SDK 21 / Android 5.0).
3. Jalankan `flutter doctor` → pastikan semua checklist hijau.
4. Siapkan HP Android: aktifkan **Opsi Pengembang** + **USB Debugging**,
   atau emulator bawaan Android Studio.
5. Clone/siapkan folder project, lalu `flutter create nota_tbs_app`.

✅ **Hasil tahap 0:** app default "Flutter Demo" bisa jalan di HP (`flutter run`).

---

## TAHAP 1 — Kerangka Project & Dependensi (± ½ hari)
File: `pubspec.yaml`
```yaml
dependencies:
  flutter: { sdk: flutter }
  google_mlkit_text_recognition: ^0.13.0   # OCR offline
  image_picker: ^1.1.2                     # kamera & galeri multi
  sqflite: ^2.3.3                          # database HP
  path: ^1.9.0
  path_provider: ^2.1.4
  syncfusion_flutter_xlsio: ^26.2.14       # export Excel
  share_plus: ^10.0.2                      # share ke WA/email
  intl: ^0.19.0
```
Struktur file di `lib/`:
```
main.dart            → UI & alur aplikasi
nota_parser.dart     → regex ekstraksi field nota
db_helper.dart       → SQLite
excel_exporter.dart  → export Excel per supplier
```
Jalankan `flutter pub get`.

✅ **Hasil tahap 1:** project bersih, library terinstall tanpa error.

---

## TAHAP 2 — Mesin OCR (Inti Aplikasi) (± 1 hari)
File: `lib/main.dart` (fungsi `_ocr`)
Alur:
1. Terima path gambar (dari kamera/galeri nanti).
2. `InputImage.fromFilePath(path)` → `TextRecognizer.processImage()`.
3. Kembalikan `String` teks mentah.
4. **TANPA UI apa pun dulu** — uji dengan `print()` hasil OCR
   pada 1 foto nota asli di HP.

```dart
Future<String> _ocr(String path) async {
  final r = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final res = await r.processImage(InputImage.fromFilePath(path));
    return res.text;
  } finally { r.close(); }
}
```

✅ **Hasil tahap 2:** teks nota terbaca penuh & benar dari foto HP
(pastikan kualitas foto bagus — ini penentu keberhasilan semua tahap).

---

## TAHAP 3 — Parser Nota (± 1 hari)
File: `lib/nota_parser.dart`
1. Dari teks OCR tahap 2, tentukan pola regex tiap field
   (untuk format **PT Perlang Sawitindo Mas** pola sudah tersedia
   di starter project: NO TIKET, RELASI, PLAT NO, PRODUK, TARRA,
   BERAT, SORTASI %, tanggal "21 Sep 2026", harga "@3090").
2. Perhatikan pemisah ribuan Indonesia: `8.460` → 8460, `4.60` → 4.6.
3. Hitung otomatis: **Total = BERAT × HARGA**.
4. Uji dengan minimal 5–10 foto nota asli; print hasil parsing.
   Kalau ada field kosong → poles regex-nya.

✅ **Hasil tahap 3:** setiap foto menghasilkan objek `Nota` lengkap
(supplier, bruto, tara, netto, berat, sortasi, harga, total).

---

## TAHAP 4 — Ambil Gambar: Kamera & Galeri (± 1 hari)
File: `lib/main.dart`
1. **Kamera:** `ImagePicker().pickImage(source: ImageSource.camera)`.
2. **Galeri banyak sekaligus:** `pickMultiImage()` → loop semua foto.
3. Setiap gambar langsung lewat tahap 2 → tahap 3 → masuk list `draft`.
4. Tambahkan indikator loading saat memproses banyak foto.

✅ **Hasil tahap 4:** bisa foto 1 nota ATAU pilih 20 foto dari galeri,
semua terbaca otomatis berurutan.

---

## TAHAP 5 — Layar Verifikasi/Edit (± 1 hari)
File: `lib/main.dart`
1. Tampilkan list hasil parsing sebagai kartu.
2. Kartu yang field wajibnya kosong → **warna merah** (CEK MANUAL).
3. Tombol edit per kartu → dialog isi: Supplier, No Tiket,
   Bruto, Tara, Netto, JJG → simpan ke objek.
4. Tombol **Simpan Semua** (aktif hanya jika list tidak kosong).

✅ **Hasil tahap 5:** tidak ada data salah yang lolos tanpa dicek manusia.

---

## TAHAP 6 — Database SQLite (± ½ hari)
File: `lib/db_helper.dart`
1. Buat tabel `nota` (tanggal, no_nota, supplier, nopol, bruto, tara,
   netto, potongan, netto_bersih, jjg, harga, total, file_foto, catatan).
2. Fungsi: `insert`, `all`, `count`, `delete`.
3. Di UI tampilkan jumlah nota tersimpan di AppBar.

✅ **Hasil tahap 6:** data tersimpan permanen di HP, tidak hilang
meski app ditutup.

---

## TAHAP 7 — Export Excel per Supplier (± 1 hari)
File: `lib/excel_exporter.dart`
1. Ambil semua data SQLite → kelompokkan per supplier.
2. Workbook: sheet **SEMUA** + 1 sheet per supplier
   (nama sheet dibersihkan, maks 31 karakter).
3. Simpan sebagai `Nota_Timbang_TANGGAL.xlsx` → `Share.shareXFiles()`
   (langsung ke WhatsApp/email).
4. Uji: buka file Excel hasilnya, pastikan sheet per supplier benar.

✅ **Hasil tahap 7:** 1 klik → file Excel terkirim ke WA kantor.

---

## TAHAP 8 — Build APK & Instalasi (± ½ hari)
1. `flutter build apk --release`
   (opsional: icon & nama app di `android/app/src/main/AndroidManifest.xml`
   dan `android/app/build.gradle`).
2. Salin `build/app/outputs/flutter-apk/app-release.apk` ke HP → install.
3. Izinkan **Kamera** dan **Penyimpanan** saat pertama buka.

✅ **Hasil tahap 8:** aplikasi jalan mandiri di HP, 100% offline.

---

## TAHAP 9 — Uji Lapangan & Tuning (berkelanjutan)
1. Uji dengan 20–50 nota asli di timbangan.
2. Catat field yang sering salah/salah baca → poles regex di
   `nota_parser.dart` → build ulang APK.
3. Tips foto: terang, tidak buram, nota penuh dalam frame, tidak miring.
4. OCR ML Kit optimal untuk nota CETAK; tulisan tangan tetap perlu
   verifikasi manual (itulah fungsi layar tahap 5).

---

## Ringkasan Urutan & Ketergantungan
```
TAHAP 0 (persiapan)
   └─> TAHAP 1 (dependensi/struktur)
        └─> TAHAP 2 (OCR) ── teks mentah
             └─> TAHAP 3 (parser) ── objek Nota
                  └─> TAHAP 4 (kamera/galeri) ── list draft
                       └─> TAHAP 5 (verifikasi UI)
                            └─> TAHAP 6 (SQLite)
                                 └─> TAHAP 7 (Excel export)
                                      └─> TAHAP 8 (APK)
                                           └─> TAHAP 9 (tuning lapangan)
```
**Estimasi total:** pemula Flutter ± 1–2 minggu; yang sudah pernah
coding Flutter ± 3–5 hari. Kode starter untuk tahap 2–7 sudah tersedia —
tinggal ikuti tahap 0–1 lalu lanjutkan sesuai urutan.
