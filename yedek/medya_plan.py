#!/usr/bin/env python3
"""Dosya (fotoğraf, ses) yedeğinin artımlı planı.

Yedek deposundaki `medya/liste.tsv.gpg` (şifreli) hangi dosyanın hangi
sürümünün yedeklendiğini tutar. Her gece yalnızca YENİ ya da DEĞİŞEN dosya
indirilip şifrelenir; kaynakta silinen dosya yedekte 14 gün daha durur
(yanlışlıkla silmeye karşı süre) sonra düşer (KVKK: silinen veri yedekte de
sonsuza kadar kalmaz; yedek süresi en çok 60 gün sözü içinde).

Liste sütunları: ad, etag, son_gorulen (YYYY-MM-DD)
Blob yolu: medya/<sha256(ad)>.gpg

Kullanım:
  medya_plan.py plan  <liste.tsv> <canli.tsv> <bugun> <cikti_dizini>
      -> indir.txt (indirilecek adlar), sil.txt (silinecek blob adları)
  medya_plan.py bitir <liste.tsv> <canli.tsv> <bugun> <basarili.txt> <yeni_liste.tsv>
"""
import datetime
import hashlib
import os
import sys

SAKLAMA_GUNU = 14


def blob(ad):
    return hashlib.sha256(ad.encode("utf-8")).hexdigest() + ".gpg"


def oku(yol, kolon):
    sonuc = {}
    if not os.path.exists(yol):
        return sonuc
    with open(yol, encoding="utf-8") as f:
        for satir in f:
            p = satir.rstrip("\n").split("\t")
            if len(p) >= kolon and p[0]:
                sonuc[p[0]] = p[1:]
    return sonuc


def plan(liste, canli, bugun, cikti):
    eski = oku(liste, 3)
    canli_haritasi = oku(canli, 2)
    indir = [
        ad for ad, (etag, *_) in canli_haritasi.items()
        if ad not in eski or eski[ad][0] != etag
    ]
    sil = []
    for ad, (_etag, son) in eski.items():
        if ad in canli_haritasi:
            continue
        yas = (bugun - datetime.date.fromisoformat(son)).days
        if yas > SAKLAMA_GUNU:
            sil.append(blob(ad))
    with open(os.path.join(cikti, "indir.txt"), "w", encoding="utf-8") as f:
        f.writelines(a + "\n" for a in sorted(indir))
    with open(os.path.join(cikti, "sil.txt"), "w", encoding="utf-8") as f:
        f.writelines(a + "\n" for a in sorted(sil))
    # Herkese açık depoda dosya sayıları yazılmaz (bkz. karsilastir.py).
    if os.environ.get("ACIK_DEPO") != "1":
        print(f"canlı: {len(canli_haritasi)}, indirilecek: {len(indir)}, silinecek: {len(sil)}")


def bitir(liste, canli, bugun, basarili, yeni):
    eski = oku(liste, 3)
    canli_haritasi = oku(canli, 2)
    tamam = set()
    if os.path.exists(basarili):
        with open(basarili, encoding="utf-8") as f:
            tamam = {s.rstrip("\n") for s in f if s.strip()}
    sonuc = {}
    for ad, (etag, *_) in canli_haritasi.items():
        if ad in tamam:
            sonuc[ad] = (etag, bugun.isoformat())
        elif ad in eski:  # yeni sürüm indirilemedi: eski kopya durur, yarın yine denenir
            sonuc[ad] = (eski[ad][0], bugun.isoformat())
    for ad, (etag, son) in eski.items():
        if ad in canli_haritasi:
            continue
        if (bugun - datetime.date.fromisoformat(son)).days <= SAKLAMA_GUNU:
            sonuc[ad] = (etag, son)
    with open(yeni, "w", encoding="utf-8") as f:
        for ad in sorted(sonuc):
            f.write(f"{ad}\t{sonuc[ad][0]}\t{sonuc[ad][1]}\n")


if __name__ == "__main__":
    komut = sys.argv[1]
    bugun = datetime.date.fromisoformat(sys.argv[4])
    if komut == "plan":
        plan(sys.argv[2], sys.argv[3], bugun, sys.argv[5])
    elif komut == "bitir":
        bitir(sys.argv[2], sys.argv[3], bugun, sys.argv[5], sys.argv[6])
    else:
        sys.exit("bilinmeyen komut")
