#!/usr/bin/env python3
# Generator kode lisensi MODEL B (terikat Kode HP) - BUSLIN BROS
# Cara pakai:  python gen_licensi.py KODE_HP YYYY-MM-DD
# Contoh:      python gen_licensi.py A3F977B2 2027-12-31
import sys, hashlib, datetime

SECRET = 'BUSLINBROS-RAHASIA-2026'

def kode_untuk(device: str, tgl: datetime.date) -> str:
    days = (tgl - datetime.date(1970, 1, 1)).days
    h = hashlib.sha256(f'{SECRET}|{device}|{days}'.encode()).hexdigest()
    digits = ''.join(c for c in h if c.isdigit())
    return digits[:10]

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('Usage: python gen_licensi.py KODE_HP YYYY-MM-DD')
        print('Contoh: python gen_licensi.py A3F977B2 2027-12-31')
        sys.exit(1)
    device = sys.argv[1].upper().replace('-', '').strip()
    tgl = datetime.date.fromisoformat(sys.argv[2])
    print(f'Kode HP {device} | s.d. {tgl} | kode: {kode_untuk(device, tgl)}')
