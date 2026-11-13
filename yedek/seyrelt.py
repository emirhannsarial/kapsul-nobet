#!/usr/bin/env python3
"""Yedek deposunda eski yedekleri seyreltir.

Kural (plan 10 ek kararı): son 7 gün her gün, son 8 hafta haftada bir.
  * yaş 0..6 gün        -> hepsi kalır
  * yaş 7..56 gün       -> her ISO haftasının EN ESKİ dosyası kalır
  * yaş > 56 gün        -> silinir

"Haftanın en eskisi" kuralı kararlıdır: kalan dosya sonraki gün da aynı
dosya olarak kalır, yani günler geçtikçe kararlar değişmez.

Kullanım: seyrelt.py <klasör> [bugün=YYYY-MM-DD] [--kuru]
Dosya adı örüntüsü: yedek-YYYY-MM-DD.<uzantı>; aynı tarihli dosyalar (dump ve
sayılar) birlikte karar alır. Silinen tarihleri yazdırır.
"""
import datetime
import os
import re
import sys

ORUNTU = re.compile(r"^yedek-(\d{4}-\d{2}-\d{2})\.")
GUNLUK = 7    # bugün dahil son 7 gün
HAFTALIK = 8  # son 8 hafta = 56 gün


def karar(tarihler, bugun):
    """Verilen tarihlerden korunacakların kümesini döndürür."""
    kalan = set()
    haftalar = {}
    for t in sorted(tarihler):
        yas = (bugun - t).days
        if yas < 0:
            kalan.add(t)  # gelecekteki tarih: dokunma
        elif yas < GUNLUK:
            kalan.add(t)
        elif yas <= HAFTALIK * 7:
            hafta = t.isocalendar()[:2]
            if hafta not in haftalar:  # sıralı gezdiğimiz için ilk = en eski
                haftalar[hafta] = t
                kalan.add(t)
    return kalan


def main(argv):
    kuru = "--kuru" in argv
    args = [a for a in argv[1:] if a != "--kuru"]
    klasor = args[0]
    bugun = (
        datetime.date.fromisoformat(args[1])
        if len(args) > 1
        else datetime.datetime.now(datetime.timezone.utc).date()
    )
    dosyalar = {}
    for ad in os.listdir(klasor):
        m = ORUNTU.match(ad)
        if m:
            dosyalar.setdefault(datetime.date.fromisoformat(m.group(1)), []).append(ad)
    kalan = karar(dosyalar.keys(), bugun)
    silinen = sorted(t for t in dosyalar if t not in kalan)
    for t in silinen:
        for ad in dosyalar[t]:
            print(f"siliniyor: {ad}")
            if not kuru:
                os.remove(os.path.join(klasor, ad))
    print(f"kalan: {len(kalan)} tarih, silinen: {len(silinen)}")


if __name__ == "__main__":
    main(sys.argv)
