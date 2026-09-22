#!/usr/bin/env python3
# Generator kode lisensi BUSLIN BROS
# Cara pakai:  python gen_licensi.py 2027-12-31
# (tanggal = batas akhir lisensi; kode 10 digit akan tercetak)
import sys, hashlib, datetime

SECRET = 'BUSLINBROS-RAHASIA-2026'

def kode_untuk(tgl: datetime.date) -> str:
    days = (tgl - datetime.date(1970, 1, 1)).days
    h = hashlib.sha256(f'{SECRET}-{days}'.encode()).hexdigest()
    digits = ''.join(c for c in h if c.isdigit())
    return digits[:10]

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: python gen_licensi.py YYYY-MM-DD')
        print('Contoh: python gen_licensi.py 2027-12-31')
        sys.exit(1)
    tgl = datetime.date.fromisoformat(sys.argv[1])
    print(f'Kode lisensi s.d. {tgl}: {kode_untuk(tgl)}')
