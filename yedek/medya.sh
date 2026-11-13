#!/usr/bin/env bash
# Dosya (fotoğraf, ses) yedeği: artımlı, dosya başına gpg şifreli, yedek
# deposunun `medya/` klasörüne. gece.sh çağırır: $1 = yedek deposu klasörü.
#
# Neden artımlı: dosyalar değişmez (yol başına bir kez yazılır); her gece
# hepsini yeniden kopyalamak hem dakika hem depo boyutu yakardı. Ücretsiz
# Supabase dosya alanı 1 GB; şifreli kopya da en çok o kadar yer tutar
# (GitHub depo başına 5 GB'a kadar rahat).
#
# İndirme: Supabase Storage'ın S3 uyumlu adresi (YEDEK_S3_ANAHTAR/GIZLI).
# service_role anahtarı bilerek kullanılmaz: o, bütün veritabanı kurallarını aşar.
set -euo pipefail
cd "$(dirname "$0")"
BETIK_DIZINI="$(pwd)"
# shellcheck source=ortak.sh
source ./ortak.sh

DEPO="$1"
MEDYA="$DEPO/medya"
KOVA="capsule-media"
SUPABASE_REF="${SUPABASE_REF:-mfqoiwdjuvancjaikuyh}"
UST_SINIR_KB=$((3 * 1024 * 1024))  # 3 GB: aşılırsa yeni dosya alınmaz, uyarı verilir

mkdir -p "$MEDYA"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
bugun="$(date -u +%F)"

# Bölge, oturum havuzu adresinden alınır (aws-0-eu-central-1.pooler...).
bolge="${YEDEK_S3_BOLGE:-$(printf '%s' "$YEDEK_DB_URL" | sed -n 's/.*aws-[0-9]*-\([a-z0-9-]*\)\.pooler.*/\1/p')}"
bolge="${bolge:-eu-central-1}"
export AWS_ACCESS_KEY_ID="$YEDEK_S3_ANAHTAR"
export AWS_SECRET_ACCESS_KEY="$YEDEK_S3_GIZLI"
export AWS_DEFAULT_REGION="$bolge"
S3_ADRESI="https://${SUPABASE_REF}.supabase.co/storage/v1/s3"

if [ -f "$MEDYA/liste.tsv.gpg" ]; then
  sifre_coz "$MEDYA/liste.tsv.gpg" > "$TMP/liste.tsv"
else
  : > "$TMP/liste.tsv"
fi

# Canlı dosya listesi (veritabanından; sekme ya da satır sonu içeren ad atlanır).
cat <<SQL | psql_calistir "$YEDEK_DB_URL" > "$TMP/canli.tsv"
select name, coalesce(metadata ->> 'eTag', metadata ->> 'size', '')
from storage.objects
where bucket_id = '${KOVA}' and name !~ E'[\\t\\n\\r]'
order by name
SQL

python3 "$BETIK_DIZINI/medya_plan.py" plan "$TMP/liste.tsv" "$TMP/canli.tsv" "$bugun" "$TMP"

: > "$TMP/basarili.txt"
basarisiz=0
alinan=0
while IFS= read -r ad; do
  [ -n "$ad" ] || continue
  kb="$(du -sk "$MEDYA" | cut -f1)"
  if [ "$kb" -gt "$UST_SINIR_KB" ]; then
    echo "::warning title=Dosya yedeği doldu::Yedek deposundaki dosya kopyası ${UST_SINIR_KB} KB sınırına ulaştı; yeni dosyalar alınmıyor."
    break
  fi
  hash="$(printf '%s' "$ad" | sha256sum | cut -d' ' -f1)"
  if aws s3 cp "s3://${KOVA}/${ad}" "$TMP/dosya.bin" --endpoint-url "$S3_ADRESI" --only-show-errors \
     && sifrele "$TMP/dosya.bin" "$MEDYA/${hash}.gpg" 65536; then
    printf '%s\n' "$ad" >> "$TMP/basarili.txt"
    alinan=$((alinan + 1))
  else
    echo "::warning title=Dosya alınamadı::Bir dosya yedeklenemedi (yarın yeniden denenecek)."
    basarisiz=$((basarisiz + 1))
  fi
  rm -f "$TMP/dosya.bin"
done < "$TMP/indir.txt"

while IFS= read -r b; do
  [ -n "$b" ] && rm -f "$MEDYA/$b"
done < "$TMP/sil.txt"

python3 "$BETIK_DIZINI/medya_plan.py" bitir "$TMP/liste.tsv" "$TMP/canli.tsv" "$bugun" \
  "$TMP/basarili.txt" "$TMP/yeni_liste.tsv"
sifrele "$TMP/yeni_liste.tsv" "$MEDYA/liste.tsv.gpg" 1015808

if [ "${ACIK_DEPO:-}" = "1" ]; then
  ozet "- Dosyalar: yedeklendi"
else
  ozet "- Dosyalar: bu gece $alinan yeni/değişen dosya yedeklendi, toplam kopya $(find "$MEDYA" -name '*.gpg' ! -name liste.tsv.gpg | wc -l)"
fi
if [ "$basarisiz" -gt 0 ]; then
  echo "::error::$basarisiz dosya yedeklenemedi (S3 anahtarını ve bölgeyi denetle)."
  exit 1
fi
