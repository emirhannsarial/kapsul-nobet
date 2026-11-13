#!/usr/bin/env bash
# Yedek betiklerinin ortak parçaları. Yalnızca `source` edilir.
#
# Bu betikler GitHub Actions'ta (ubuntu-latest) çalışır: docker, gpg, python3,
# git ve aws komutları hazır gelir. Hiçbir betik `set -x` kullanmaz: gizli
# değişkenler günlüğe düşmesin.

# Yedeğe DAHİL OLMAYAN tablo verileri: oturumlar IP ve cihaz bilgisi taşır,
# yenilenince zaten yeniden oluşur; yedekte saklamak gereksiz veri olurdu
# (docs/veri_envanteri.md → yedekler). Şemaları yedekte durur.
HARIC_VERI=(
  auth.sessions
  auth.refresh_tokens
  auth.flow_state
  auth.one_time_tokens
  auth.audit_log_entries
  auth.mfa_challenges
)

# Yedeklenen şemalar. cron, vault, extensions yedeğe girmez: pg_cron işleri
# migration'lardan, uzantılar Supabase'den gelir.
YEDEK_SEMALARI=(public private auth storage)

SEKME="$(printf '\t')"

# Satır sayısı sorgusu: "şema.tablo<TAB>sayı". Geri yükleme denemesinde
# yedekten çıkan veritabanı bununla kaynakla karşılaştırılır.
sayi_sorgusu() {
  cat <<'SQL'
select n.nspname || '.' || c.relname,
       (xpath('/row/c/text()',
              query_to_xml(format('select count(*) as c from %I.%I',
                                  n.nspname, c.relname), false, true, '')))[1]::text
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind in ('r', 'p')
  and n.nspname in ('public', 'private', 'auth', 'storage')
order by 1
SQL
}

# psql'i postgres:17 konteynerinde çalıştırır (Supabase PostgreSQL 17;
# runner'daki psql daha eski olabilir). $1: bağlantı adresi, stdin: sorgu.
psql_calistir() {
  docker run --rm -i -e "PGURL=$1" postgres:17 \
    sh -c 'psql "$PGURL" --no-psqlrc -v ON_ERROR_STOP=1 -At -F "$(printf "\t")"'
}

# Basit gpg simetrik şifreleme. $1: girdi, $2: çıktı, $3: s2k tekrar sayısı.
sifrele() {
  gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3 \
    --symmetric --cipher-algo AES256 --compress-algo none \
    --s2k-mode 3 --s2k-digest-algo SHA512 --s2k-count "${3:-65011712}" \
    -o "$2" "$1" 3<<<"$YEDEK_SIFRE"
}

# $1: şifreli girdi, stdout'a açık hali.
sifre_coz() {
  gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 \
    -d "$1" 3<<<"$YEDEK_SIFRE"
}

ozet() { # GitHub Actions özet sayfasına satır ekler
  echo "$@" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# Yedek deposuna SSH erişimi kurar (yalnızca o depoya yazan deploy key).
# Sonra: git clone "git@github.com:${YEDEK_DEPO}.git" ...
ssh_kur() {
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  printf '%s\n' "$YEDEK_DEPO_ANAHTARI" > ~/.ssh/yedek_anahtar
  chmod 600 ~/.ssh/yedek_anahtar
  ssh-keyscan -t ed25519,rsa github.com >> ~/.ssh/known_hosts 2>/dev/null
  export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/yedek_anahtar -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
}

# Yönetim paneli için sonuç kaydı (private.backup_log). Başarısızlık yedeği
# bozmasın: hata yalnızca uyarı olur. $1: backup|restore_test, $2: true|false, $3: boyut (KB, isteğe bağlı).
yedek_kaydet() {
  [ -n "${YEDEK_DB_URL:-}" ] || return 0
  local boyut="${3:-null}"
  printf "insert into private.backup_log (kind, ok, size_kb) values ('%s', %s, %s);
" "$1" "$2" "$boyut"     | psql_calistir "$YEDEK_DB_URL" >/dev/null     || echo "::warning title=Yedek kaydı yazılamadı::private.backup_log satırı eklenemedi (panel yedek yaşını gösteremez)."
}
