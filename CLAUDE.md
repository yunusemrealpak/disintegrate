# disintegrate

Flutter paketi: herhangi bir widget'ı parçacıklara ayırıp dağıtan bir fragment
shader. Mimari gerekçeler `README.md` içinde — koda dokunmadan önce oku.

## Kritik kurallar

- **Efekt tek bir `0..1` değerinin fonksiyonudur.** `DisintegrateEffect` state
  tutmaz. Birden fazla widget aynı anda dağılacaksa **tek** bir
  `AnimationController` kullan ve her widget'a kendi dilimini ver; widget başına
  controller açma.
- **Engine uniform'ları en üstte kalmalı.** `.frag` içinde `uSize` (vec2) ve
  `uTexture` (sampler2D) sırasıyla ilk iki uniform. Araya bir şey koyarsan
  engine yanlış slot'a yazar ve efekt sessizce bozulur.
- **Uniform slot indeksi tahmin edilmez.** Engine'in yazdığı vec2'nin float
  slot'ları kapsayıp kapsamadığı sürüme göre değişiyor;
  `DisintegrateProgram.firstFloatSlot` bunu bir kez **probe** ederek bulur
  (sınır dışına yazma denemesi throw ediyorsa taban 0'dır). Sabit yazma.
- **Mesafeler logical px olarak authored, physical px olarak set edilir.**
  Dart tarafı `devicePixelRatio` ile çarpar. Shader'da `FlutterFragCoord()`
  physical pixel verir.
- **`progress == 0` bedava olmalı.** Filtre, shader, ekstra layer yok — child
  doğrudan döner. `progress == 1`'de child layout'ta ve state'iyle kalır ama
  boyanmaz. İkisinin de testi var; bozarsan test düşer.
- **Aynı `FragmentShader` nesnesini tekrar verme.** `ImageFilter.shader` aynı
  shader'ı sarınca `==` eşit çıkıyor, `ImageFiltered` de repaint istemiyor:
  uniform'lar güncelleniyor ama ekrana hiç gitmiyor, sonra scroll gibi alakasız
  bir repaint'te efekt birden beliriyor. Paket iki shader tutup sırayla
  kullanıyor; tampon `didUpdateWidget`'ta değişiyor ki `build` saf kalsın.
- **Premultiplied alpha.** Sampler premultiplied veriyor; texel'i skalerle
  çarpmak premultiplied'ı korur. Ayrı ayrı rgb/a çarpma.

## Ayarlanmış sabitler ve nedenleri

| Değer | Neden |
| --- | --- |
| `sweep` varsayılan `0.35` | `0.75`'te yüzeyde sert bir bant geziyordu; silme efekti gibi duruyordu, dağılma gibi değil |
| `scatter` varsayılan `1.2` rad | 0'da bütün taneler aynı vektörde gidiyor: delikli bir öteleme, saçılma değil |
| hız `mix(0.4, 1.8, rnd)` | Tek hızda bulut dağılmıyor, blok hâlinde kayıyor |
| `travel` = `1 - (1-local)²` (ease-out) | Hızlanan uçuş "itiliyor" gibi duruyor; bırakılma hissi için hızlı kopup yavaşlaması gerek |
| `fade` = `1 - smoothstep(0.3, 1, local)` | Uzun kuyruk: taneler uçuşun çoğunda görünür kalıp incelerek kayboluyor |
| grain yarıçapı `mix(0.78, 0.02, travel)` | Küçülmeyen hücre = yüzeyde delik açılması = glitch görüntüsü |
| grain maskesinin `smoothstep(0.0, 0.18, local)` ile açılması | Yoksa `progress = 0.01`'de widget aniden halftone deseni giyiyor |
| Demo `particleSize: 1.3` | `2.5` iri ve köşeli duruyordu; toz değil moloz |
| Demo **açık tema** | Koyu zeminde koyu toz görünmüyor; efekt vardı ama okunmuyordu |

**Toz kartın dışına çıkamaz.** Shader filtresi yalnız kendisine verilen yüzeyi
boyayabiliyor. `spread` bunun için var ve **layout yer kaplar** — demo, kartların
kendi margin'ini bırakıp boşluğu spread'e devrediyor.

## Simülatör

- Cihaz: iPhone 17e → `26AB9883-DFE9-41F7-A132-A3C25A584656` (UDID değişebilir,
  `xcrun simctl list devices booted` ile doğrula)
- Aksiyon butonu merkezi: **(195, 766)** point. Layout değişirse
  `idb ui describe-all` ile yeniden bul.
- `.frag` değiştirdikten sonra hot reload/restart yetmez — shader build sırasında
  derleniyor, tam yeniden `flutter run` gerekir.
- Simülatörde `--release` / `--profile` yok; fps ölçümü gerçek cihaz ister.

## Demo reel

```bash
tool/record_demo.sh <udid> /tmp/raw.mp4   # kayıt + jestler tek process
tool/make_reel.sh /tmp/raw.mp4            # -> doc/demo.mp4 + doc/demo.gif
```

Kayıt ve jestler tek process'te koşar; ayrı çağrılar arasındaki gecikme videoya
ölü zaman olarak girer. Uygulama **dağılmamış** durumdayken başlat, yoksa reel
ters sırada çıkar.

GIF'in segment zamanları `make_reel.sh` içinde sabit ve `doc/demo.mp4`'e göredir.
Tek global palet + dither yok: PIL kareler arası farkı ancak paletler eşitse
üretiyor, dither gürültüsü dosyayı iki katına çıkarıyor.

ffmpeg yok; her şey AVFoundation üzerinden (`tool/demo_transcode.swift`,
`tool/demo_frames.swift`).
