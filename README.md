# kapsul-nobet

InTimePost'un iki gece/saatlik bakım işi. **Burada uygulama kodu yok.**

- **Yedek** (`.github/workflows/yedek.yml`, her gece 05:41 Türkiye): veritabanı
  dökümü parolayla şifrelenir (gpg AES256) ve ayrı, **özel** bir depoya yazılır.
  Parola, veritabanı adresi ve yazma anahtarı GitHub'ın şifreli sır kasasında
  durur; günlüğe hiçbir değer, sayı ya da hata ayrıntısı yazılmaz.
- **Nöbetçi** (`.github/workflows/nobetci.yml`, saatte bir): Supabase projesini
  uyanık tutar; bildirim zamanlayıcısı, acil şikâyet ve kapasite sağlığını
  denetler. Uygulamanın içindeki herkese açık anahtarı kullanır.
- **Canlı tut** (ayda bir): GitHub 60 gün commit almayan açık depolarda
  zamanlanmış işleri kapattığı için küçük bir tarih commit'i.

Herhangi bir iş kırmızıya dönerse GitHub depo sahibine e-posta atar.
Kurulum ve geri yükleme: ana (özel) depoda `docs/ceo_gorevleri.md` →
*Gece yedeği kurulumu*.
