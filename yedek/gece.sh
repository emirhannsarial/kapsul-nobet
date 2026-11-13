#!/usr/bin/env bash
# Gece yedeği: veritabanı dökümü (+ isteğe bağlı dosyalar) şifrelenip AYRI
# ÖZEL bir GitHub deposuna commit edilir. Actions artifact'ı kullanılmaz
# (GitHub depolama aşımı dersi, plan 10 ek kararı).
#
# Gerekli sırlar (GitHub → Settings → Secrets and variables → Actions):
#   YEDEK_DB_URL          Supabase "Session pooler" bağlantı adresi
#   YEDEK_SIFRE           yedeği şifreleyen parola (CEO saklar)
#   YEDEK_DEPO_ANAHTARI   yedek deposuna yazma yetkili deploy key (özel anahtar)
# İsteğe bağlı (dosya yedeği): YEDEK_S3_ANAHTAR, YEDEK_S3_GIZLI
#
# Sırlar girilmemişse ya da bir şey ters giderse iş KIRMIZI biter.
set -euo pipefail
cd "$(dirname "$0")"
BETIK_DIZINI="$(pwd)"
# shellcheck source=ortak.sh
source ./ortak.sh

YEDEK_DEPO="${YEDEK_DEPO:-emirhannsarial/kapsul-yedek}"

eksik=()
for ad in YEDEK_DB_URL YEDEK_SIFRE YEDEK_DEPO_ANAHTARI; do
  [ -n "${!ad:-}" ] || eksik+=("$ad")
done
if [ ${#eksik[@]} -gt 0 ]; then
  # Eskiden "atlandı" deyip YEŞİL bitiyordu: iki ay boyunca hiç yedek
  # alınmadı ve kimse fark etmedi (güvenlik denetimi 12 Kasım 2026, K2).
  # Artık KIRMIZI: GitHub e-posta atar.
  echo "::error title=Yedek ALINMADI::Gizli değişken girilmemiş: ${eksik[*]}. Bu depoda (kapsul-nobet) Settings → Secrets and variables → Actions. Adımlar: ana depoda docs/ceo_gorevleri.md → Gece yedeği kurulumu."
  ozet "### Yedek ALINMADI"
  ozet "Şu gizli değişkenler girilmemiş: \`${eksik[*]}\`. Adımlar: ana depoda \`docs/ceo_gorevleri.md\` → *Gece yedeği kurulumu*."
  exit 1
fi

CALISMA="$(mktemp -d)"
trap 'rm -rf "$CALISMA"' EXIT
tarih="$(date -u +%F)"

ssh_kur
DEPO="$CALISMA/depo"
if ! git clone --depth 1 "git@github.com:${YEDEK_DEPO}.git" "$DEPO" 2>&1 | sed 's/^/git: /'; then
  :
fi
if [ ! -d "$DEPO/.git" ]; then
  echo "::error::Yedek deposuna erişilemedi (${YEDEK_DEPO}). Depo adı, deploy key ve 'Allow write access' ayarını denetle."
  exit 1
fi
git -C "$DEPO" config user.name "yedek-botu"
git -C "$DEPO" config user.email "yedek-botu@users.noreply.github.com"

# --- Döküm ------------------------------------------------------------------
echo "Satır sayıları (önce)..."
sayi_sorgusu | psql_calistir "$YEDEK_DB_URL" > "$CALISMA/once.tsv"

dump_secenekleri=(-Fc --no-owner --no-privileges)
for s in "${YEDEK_SEMALARI[@]}"; do dump_secenekleri+=(-n "$s"); done
for t in "${HARIC_VERI[@]}"; do dump_secenekleri+=(--exclude-table-data="$t"); done

echo "pg_dump çalışıyor..."
docker run --rm -e "PGURL=$YEDEK_DB_URL" postgres:17 \
  sh -c 'pg_dump "$PGURL" "$@"' sh "${dump_secenekleri[@]}" > "$CALISMA/dump.bin"

echo "Satır sayıları (sonra)..."
sayi_sorgusu | psql_calistir "$YEDEK_DB_URL" > "$CALISMA/sonra.tsv"

# Döküm gerçekten okunabilir mi ve içinde bir şey var mı?
girdi_sayisi="$(docker run --rm -i postgres:17 pg_restore --list < "$CALISMA/dump.bin" | grep -c '^[0-9]' || true)"
if [ "$girdi_sayisi" -lt 50 ]; then
  echo "::error::Döküm şüpheli derecede küçük ($girdi_sayisi girdi). Yedek yazılmadı."
  exit 1
fi

# --- Şifrele ve doğrula -----------------------------------------------------
sifrele "$CALISMA/dump.bin" "$DEPO/yedek-$tarih.dump.gpg"
ilk="$(sha256sum < "$CALISMA/dump.bin")"
son="$(sifre_coz "$DEPO/yedek-$tarih.dump.gpg" | sha256sum)"
if [ "$ilk" != "$son" ]; then
  echo "::error::Şifrelenen yedek geri açılınca aynı çıkmadı. Yedek yazılmadı."
  exit 1
fi
boyut="$(stat -c %s "$DEPO/yedek-$tarih.dump.gpg")"
if [ "$boyut" -gt $((90 * 1024 * 1024)) ]; then
  echo "::error::Yedek 90 MB'ı aştı ($((boyut / 1048576)) MB); GitHub tek dosyayı 100 MB'da reddeder. Yedeği parçalara bölmek gerekiyor."
  exit 1
fi

# Satır sayıları: tablo, yedekten önce, yedekten sonra (geri yükleme denemesi için).
join -t "$SEKME" -j 1 <(sort -t "$SEKME" -k1,1 "$CALISMA/once.tsv") \
  <(sort -t "$SEKME" -k1,1 "$CALISMA/sonra.tsv") > "$DEPO/yedek-$tarih.sayilar.tsv"

# --- Seyreltme (son 7 gün her gün, son 8 hafta haftada bir) -----------------
python3 "$BETIK_DIZINI/seyrelt.py" "$DEPO" "$tarih"

# --- Dosyalar (isteğe bağlı) ------------------------------------------------
medya_hatasi=0
if [ -n "${YEDEK_S3_ANAHTAR:-}" ] && [ -n "${YEDEK_S3_GIZLI:-}" ]; then
  # Dosya hatası veritabanı yedeğini engellemesin: önce yaz, sonra kırmızıya dön.
  bash "$BETIK_DIZINI/medya.sh" "$DEPO" || medya_hatasi=1
else
  echo "::notice title=Dosyalar atlandı::YEDEK_S3_ANAHTAR / YEDEK_S3_GIZLI girilmemiş; yalnızca veritabanı yedeklendi."
  ozet "Dosya (fotoğraf, ses) yedeği atlandı: S3 anahtarları girilmemiş."
fi

# --- Yedek deposuna yaz: tek commit, geçmiş tutulmaz -------------------------
# Silinen eski yedekler git geçmişinde kalırsa depo her gün büyürdü.
# Her gece geçmiş sıfırlanır (orphan commit + force push); eski dosyalar
# GitHub'dan da düşer. Yedeğin "geçmişi" dosya adlarındaki tarihlerdir.
cat > "$DEPO/OKU.md" <<'MD'
# Kapsül yedekleri (şifreli)

Bu depo InTimePost'un gece yedeğidir; **elle düzenlenmez**, her gece bir
GitHub Actions işi (`kapsul-nobet` deposunda `yedek/gece.sh`) yazar. İçindeki her şey parolayla
şifrelidir; parola yalnızca CEO'dadır ve bu depoda yoktur.

- `yedek-YYYY-AA-GG.dump.gpg`: veritabanı dökümü (pg_dump özel biçim, gpg AES256)
- `yedek-YYYY-AA-GG.sayilar.tsv`: tablo başına satır sayısı (geri yükleme denemesi için)
- `medya/`: fotoğraf ve ses dosyalarının şifreli kopyası (varsa)

Geri yükleme: ana depoda `docs/ceo_gorevleri.md` → *Gece yedeği kurulumu*.
MD
git -C "$DEPO" symbolic-ref HEAD refs/heads/gecici
git -C "$DEPO" add -A
git -C "$DEPO" commit -q -m "Yedek $tarih"
git -C "$DEPO" push -q --force origin gecici:refs/heads/main

kb="$(du -sk --exclude=.git "$DEPO" | cut -f1)"
if [ "$kb" -gt $((3 * 1024 * 1024)) ]; then
  echo "::warning title=Yedek deposu büyüyor::Yedek deposu $((kb / 1024)) MB. GitHub 5 GB üstünü önermiyor; dosya yedeğinin sınırlanması gerekebilir."
fi

yedek_kaydet backup true "$((boyut / 1024))"
ozet "### Yedek alındı: $tarih"
ozet "- Döküm: $((boyut / 1024)) KB (şifreli), $girdi_sayisi nesne"
ozet "- Depo (dosyalar dahil): $((kb / 1024)) MB"
ozet "- Kalan yedekler: $(find "$DEPO" -maxdepth 1 -name '*.dump.gpg' | wc -l)"

if [ "$medya_hatasi" -ne 0 ]; then
  echo "::error::Veritabanı yedeği yazıldı ama dosya yedeği tamamlanamadı."
  exit 1
fi
