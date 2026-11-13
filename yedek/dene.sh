#!/usr/bin/env bash
# Aylık geri yükleme denemesi: en yeni yedek geçici bir Postgres
# konteynerine geri yüklenir, tablo satır sayıları yedek anındaki sayılarla
# karşılaştırılır. Geri yüklenmemiş yedek, yedek sayılmaz (docs/kalite.md §5).
#
# Sırlar yoksa "atlandı" der, yeşil biter (bkz. gece.sh).
set -euo pipefail
cd "$(dirname "$0")"
BETIK_DIZINI="$(pwd)"
# shellcheck source=ortak.sh
source ./ortak.sh

YEDEK_DEPO="${YEDEK_DEPO:-emirhannsarial/kapsul-yedek}"
if [ -z "${YEDEK_SIFRE:-}" ] || [ -z "${YEDEK_DEPO_ANAHTARI:-}" ]; then
  echo "::notice title=Geri yükleme denemesi atlandı::Yedek sırları girilmemiş."
  ozet "### Geri yükleme denemesi atlandı (sırlar girilmemiş)"
  exit 0
fi

CALISMA="$(mktemp -d)"
KONTEYNER="yedek-deneme"
trap 'docker rm -f "$KONTEYNER" >/dev/null 2>&1 || true; rm -rf "$CALISMA"' EXIT

ssh_kur
if ! git clone --depth 1 "git@github.com:${YEDEK_DEPO}.git" "$CALISMA/depo" >/dev/null 2>&1; then
  echo "::error::Yedek deposuna erişilemedi (${YEDEK_DEPO})."
  exit 1
fi

dosya="${DENEME_DOSYASI:-$(find "$CALISMA/depo" -maxdepth 1 -name '*.dump.gpg' -printf '%f\n' | sort | tail -1)}"
if [ -z "$dosya" ]; then
  echo "::error::Yedek deposunda hiç yedek yok."
  exit 1
fi
sayilar="$CALISMA/depo/${dosya%.dump.gpg}.sayilar.tsv"
echo "Denenen yedek: $dosya"

sifre_coz "$CALISMA/depo/$dosya" > "$CALISMA/dump.bin"

docker run -d --name "$KONTEYNER" -e POSTGRES_PASSWORD=deneme postgres:17 > /dev/null
for _ in $(seq 1 30); do
  docker exec "$KONTEYNER" pg_isready -U postgres > /dev/null 2>&1 && break
  sleep 2
done
docker exec "$KONTEYNER" pg_isready -U postgres > /dev/null

# Supabase'in kendi rolleri ve uzantı şeması: dökümde bunlara başvuru var.
docker exec -i "$KONTEYNER" psql -U postgres -v ON_ERROR_STOP=1 -q <<'SQL'
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role authenticator noinherit login;
create role supabase_auth_admin nologin;
create role supabase_storage_admin nologin;
create role supabase_admin nologin;
create role dashboard_user nologin;
create schema extensions;
create extension pgcrypto schema extensions;
create extension "uuid-ossp" schema extensions;
create extension pg_trgm schema extensions;
alter database postgres set search_path = "$user", public, extensions;
SQL

echo "Geri yükleniyor..."
docker exec -i "$KONTEYNER" pg_restore -U postgres -d postgres \
  --no-owner --no-privileges < "$CALISMA/dump.bin" 2> "$CALISMA/hatalar.txt" || true
hata_sayisi="$(grep -c 'error:' "$CALISMA/hatalar.txt" || true)"
echo "pg_restore hata satırı: $hata_sayisi"
# Herkese açık depoda hata satırları yazılmaz: anahtar değerleri içerebilir.
if [ "$hata_sayisi" -gt 0 ] && [ "${ACIK_DEPO:-}" != "1" ]; then
  echo "::group::pg_restore hataları (ilk 40)"
  grep 'error:' "$CALISMA/hatalar.txt" | head -40
  echo "::endgroup::"
fi

sayi_sorgusu | docker exec -i "$KONTEYNER" psql -U postgres --no-psqlrc -At -F "$SEKME" \
  > "$CALISMA/yuklenen.tsv"

set +e
python3 "$BETIK_DIZINI/karsilastir.py" "$sayilar" "$CALISMA/yuklenen.tsv" "${HARIC_VERI[@]}" \
  | tee "$CALISMA/rapor.txt"
sonuc=${PIPESTATUS[0]}
set -e

ozet "### Geri yükleme denemesi: $dosya"
ozet "pg_restore hata satırı: $hata_sayisi"
ozet '```'
tail -n 40 "$CALISMA/rapor.txt" | while IFS= read -r satir; do ozet "$satir"; done
ozet '```'
if [ "$sonuc" -ne 0 ]; then
  echo "::error title=Geri yükleme denemesi başarısız::Yedekten çıkan veritabanı kaynakla uyuşmuyor. Yedek güvenilir sayılmaz; ayrıntı iş günlüğünde."
  yedek_kaydet restore_test false
  exit 1
fi
yedek_kaydet restore_test true
echo "Geri yükleme denemesi başarılı."
