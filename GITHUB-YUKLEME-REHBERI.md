# LaceDrop'u GitHub'a yükleme

Bu pakette GitHub deposuna konulacak kaynaklar ve GitHub Releases bölümüne eklenecek çalışır uygulama ayrı hazırlanmıştır.

## 1. Depoyu oluştur

1. GitHub'da **New repository** düğmesine bas.
2. Repository name alanına `LaceDrop` yaz.
3. Kısa açıklama olarak şunu kullanabilirsin:

   `Interactive crochet lace overlay for macOS with real-time cloth physics.`

4. **Public** seçeneğini işaretle.
5. README, `.gitignore` veya lisans ekleme; bunlar pakette zaten var.
6. **Create repository** düğmesine bas.

## 2. Kaynakları yükle

`LaceDrop-GitHub-Source-v0.7.0.zip` dosyasını bilgisayarında aç. Finder'da kaynak klasörünü açıp `⌘ Shift .` tuşlarına bas; bu işlem `.github` ve `.gitignore` dosyalarını görünür yapar. Ardından klasörün **içindeki her şeyi** GitHub'daki **Add file → Upload files** sayfasına sürükle.

Yükleme listesinde şunların bulunduğunu kontrol et:

```text
.github/
.gitignore
Sources/
ScreenSaver/
Resources/
README.md
LICENSE
build.sh
```

Commit mesajı:

```text
Initial public release of LaceDrop
```

ZIP dosyasını veya `LaceDrop-Source` klasörünün kendisini doğrudan kaynak deposuna yükleme. Klasörün içeriği deponun ana dizininde görünmeli.

## 3. v0.7.0 sürümünü yayınla

1. Deponun sağ tarafındaki **Releases** bölümüne gir.
2. **Draft a new release** düğmesine bas.
3. Yeni etiket oluştur: `v0.7.0`
4. Release title: `LaceDrop v0.7.0`
5. Açıklama için `RELEASE_NOTES_v0.7.0.md` dosyasındaki metni kullan.
6. Çalışır uygulama olarak `LaceDrop-v0.7.0.zip` dosyasını ekle.
7. **Publish release** düğmesine bas.

## 4. Konu etiketleri

Deponun **About** bölümüne şu etiketleri ekleyebilirsin:

```text
macos objective-c metal cloth-simulation screensaver desktop-customization
```

## Not

Hazır v0.7.0 uygulaması Apple Silicon Mac'ler için derlenmiştir ve Apple tarafından noterlenmemiştir. Kullanıcılar ilk açılışta uygulamaya sağ tıklayıp **Aç** seçeneğini kullanmak zorunda kalabilir.
