#!/usr/bin/env python3
"""Geri yüklenen veritabanının satır sayılarını yedek anındaki sayılarla karşılaştırır.

Kullanım: karsilastir.py <sayilar.tsv> <geri_yuklenen.tsv> <haric_tablo>...
  sayilar.tsv: "tablo<TAB>yedekten_once<TAB>yedekten_sonra"
  geri_yuklenen.tsv: "tablo<TAB>sayı"
Yedek alınırken tablolara yazılabildiği için tam eşitlik aranmaz: geri yüklenen
sayı, [min(önce, sonra), max(önce, sonra)] aralığında (payla birlikte) olmalı.
Pay: en az 3 satır ya da yüzde 2. Hariç tutulan tabloların VERİSİ yedeğe
alınmaz; yalnızca varlığı denetlenir. Uyuşmazlıkta çıkış kodu 1.
"""
import os
import sys

# Herkese açık depoda (kapsul-nobet) günlük herkese görünür: satır sayıları
# (kullanıcı, kapsül sayısı) yazılmaz, yalnızca tablo adı ve sonuç.
ACIK = os.environ.get("ACIK_DEPO") == "1"


def oku(yol, kolon):
    sonuc = {}
    with open(yol, encoding="utf-8") as f:
        for satir in f:
            p = satir.rstrip("\n").split("\t")
            if len(p) >= kolon:
                sonuc[p[0]] = [int(x) for x in p[1:kolon]]
    return sonuc


def main():
    kaynak = oku(sys.argv[1], 3)
    yuklenen = oku(sys.argv[2], 2)
    haric = set(sys.argv[3:])
    hatalar = []
    for tablo, (once, sonra) in sorted(kaynak.items()):
        if tablo not in yuklenen:
            hatalar.append(f"EKSİK   {tablo} geri yüklenen veritabanında yok")
            continue
        if tablo in haric:
            print(f"atlandı {tablo} (verisi yedeğe alınmaz)")
            continue
        n = yuklenen[tablo][0]
        alt, ust = min(once, sonra), max(once, sonra)
        pay = max(3, int(ust * 0.02))
        durum = "tamam  " if alt - pay <= n <= ust + pay else "FARKLI "
        ayrinti = "" if ACIK else f": kaynak {once}->{sonra}, geri yüklenen {n}"
        print(f"{durum} {tablo}{ayrinti}")
        if durum.startswith("FARKLI"):
            hatalar.append(f"FARKLI  {tablo}{ayrinti}")
    print(f"\n{len(kaynak)} tablo karşılaştırıldı, {len(hatalar)} sorun.")
    for h in hatalar:
        print(h)
    sys.exit(1 if hatalar else 0)


main()
