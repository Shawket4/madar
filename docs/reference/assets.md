Perfect! Now let me compile a final comprehensive report with all the gathered information.

---

## BRAND ASSET INVENTORY FOR NEW FLUTTER APP

### 1. LOGOS & LOCKUPS

**Madar-Assets (Primary Source - /Users/shawket/Downloads/Madar-Assets/)**

**Lockups** (symbol + wordmark combinations):
- `/Users/shawket/Downloads/Madar-Assets/png/lockups/lockup-latin.png` — 1600x1530, light on transparent (primary)
- `/Users/shawket/Downloads/Madar-Assets/png/lockups/lockup-latin-reversed.png` — 1600x1530, light on transparent (dark bg variant)
- `/Users/shawket/Downloads/Madar-Assets/png/lockups/lockup-arabic.png` — 1153x1600, light on transparent
- `/Users/shawket/Downloads/Madar-Assets/png/lockups/lockup-arabic-reversed.png` — 1153x1600, light on transparent (dark bg)
- `/Users/shawket/Downloads/Madar-Assets/png/lockups/lockup-bilingual.png` — 1600x1293 (Latin over Arabic)
- `/Users/shawket/Downloads/Madar-Assets/png/lockups/lockup-bilingual-reversed.png` — 1600x1293 (dark bg variant)
- SVG versions also available in `/Users/shawket/Downloads/Madar-Assets/svg/lockups/`

**Wordmarks** (text/logotype only):
- `/Users/shawket/Downloads/Madar-Assets/png/wordmark-latin/wordmark-primary.png` — 1600x486, primary brand colour (#0D6273 teal)
- `/Users/shawket/Downloads/Madar-Assets/png/wordmark-latin/wordmark-reversed.png` — 1600x486, light on transparent (dark bg)
- `/Users/shawket/Downloads/Madar-Assets/png/wordmark-latin/wordmark-mono-ink.png` — 1600x486, solid black/ink
- `/Users/shawket/Downloads/Madar-Assets/png/wordmark-latin/wordmark-mono-paper.png` — 1600x486, white (#EFF3F4)
- `/Users/shawket/Downloads/Madar-Assets/png/wordmark-arabic/` — 4 variants (tashkeel & plain forms, ink & paper)

**Symbol** (orbit mark alone):
- `/Users/shawket/Downloads/Madar-Assets/png/symbol/symbol-primary.png` — 1600x1600, teal primary
- `/Users/shawket/Downloads/Madar-Assets/png/symbol/symbol-reversed.png` — 1600x1600, white on transparent
- `/Users/shawket/Downloads/Madar-Assets/png/symbol/symbol-on-teal.png` — 1600x1600, teal variant
- `/Users/shawket/Downloads/Madar-Assets/png/symbol/symbol-mono-ink.png` — 1600x1600, black
- `/Users/shawket/Downloads/Madar-Assets/png/symbol/symbol-mono-paper.png` — 1600x1600, white
- `/Users/shawket/Downloads/Madar-Assets/png/symbol/symbol-favicon.png` — 1600x1600, node-less variant for small sizes

**App Icon Tiles** (rounded background baked in):
- `/Users/shawket/Downloads/Madar-Assets/png/app-icons/icon-symbol-ink.png` — 1600x1600
- `/Users/shawket/Downloads/Madar-Assets/png/app-icons/icon-symbol-light.png` — 1600x1600
- `/Users/shawket/Downloads/Madar-Assets/png/app-icons/icon-symbol-teal.png` — 1600x1600
- `/Users/shawket/Downloads/Madar-Assets/png/app-icons/icon-latin-ink.png` — 1600x1600
- `/Users/shawket/Downloads/Madar-Assets/png/app-icons/icon-latin-light.png` — 1600x1600
- `/Users/shawket/Downloads/Madar-Assets/png/app-icons/icon-latin-teal.png` — 1600x1600
- `/Users/shawket/Downloads/Madar-Assets/png/app-icons/icon-arabic-ink.png` — 1600x1600
- `/Users/shawket/Downloads/Madar-Assets/png/app-icons/icon-arabic-light.png` — 1600x1600
- `/Users/shawket/Downloads/Madar-Assets/png/app-icons/icon-arabic-teal.png` — 1600x1600

**Recommendations for Flutter App:**
- **App Icon**: Use `icon-symbol-teal.png` or `icon-latin-teal.png` (1600x1600) — pre-rounded, consistent with native apps
- **Splash/Launch Screen**: Use `lockup-latin.png` (1600x1530) on light background, or `lockup-latin-reversed.png` on dark
- **In-App Rail/Navigation Lockup**: Light theme → `lockup-latin.png`; Dark theme → `lockup-latin-reversed.png`
- **Favicon/Small Icon**: `symbol-favicon.png` (1600x1600)

### 2. FONTS

**Cairo Font Family** — All 5 weights bundled in both native apps and old Flutter app

**Files & Weights:**
- `Cairo-Regular.ttf` — Weight 400
- `Cairo-Medium.ttf` — Weight 500
- `Cairo-SemiBold.ttf` — Weight 600
- `Cairo-Bold.ttf` — Weight 700
- `Cairo-ExtraBold.ttf` — Weight 800

**Locations:**
- Kotlin (Compose): `/Users/shawket/Desktop/madar-pos/kotlin-app/composeApp/src/commonMain/composeResources/font/`
- Swift: `/Users/shawket/Desktop/madar-pos/swift-app/Resources/Fonts/`
- Old Flutter (sufrix_pos): `/Users/shawket/Desktop/sufrix_pos/assets/fonts/`

**Flutter pubspec.yaml Declaration** (from sufrix_pos):
```yaml
flutter:
  fonts:
    - family: Cairo
      fonts:
        - asset: assets/fonts/Cairo-Regular.ttf
          weight: 400
        - asset: assets/fonts/Cairo-Medium.ttf
          weight: 500
        - asset: assets/fonts/Cairo-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Cairo-Bold.ttf
          weight: 700
        - asset: assets/fonts/Cairo-ExtraBold.ttf
          weight: 800
```

**Copy these 5 files to new Flutter app at**: `assets/fonts/Cairo-*.ttf`

### 3. PLACEHOLDER/MENU ITEM IMAGERY

**Icon PDFs in Swift app** (100+ system icons):
- `/Users/shawket/Desktop/madar-pos/swift-app/Resources/Assets.xcassets/Icons/`
  - 120+ PDF icons (delete, leaf, settings, chevron-*, arrow-*, circle-*, etc.)
  - All rendered via PDF in Xcode (scalable vector)
  - Examples: menu.pdf, star.pdf, shopping-cart.pdf, utensils-crossed.pdf, croissant.pdf, coffee.pdf, sandwich.pdf, ice-cream-cone.pdf

**Kotlin App Icon XML Drawables**:
- `/Users/shawket/Desktop/madar-pos/kotlin-app/composeApp/src/commonMain/composeResources/drawable/`
  - 100+ XML vector drawables (ic_*.xml)
  - Material Design compatible

**Old Flutter App Sounds Directory**:
- `/Users/shawket/Desktop/sufrix_pos/assets/lottie/` — Lottie animations (referenced in pubspec.yaml)

**Recommendation**: For menu/category/item placeholder art, consider:
- Category icons: use existing PDF/XML set from native apps (reuse vectors)
- Food item photos: generate or fetch from remote (not pre-bundled in natives currently)

### 4. APP ICON SOURCES & NATIVE CONFIGURATIONS

**Android (Kotlin/Compose)**:
- **Adaptive Icon Config**: `/Users/shawket/Desktop/madar-pos/kotlin-app/composeApp/src/androidMain/res/mipmap-anydpi-v26/ic_launcher.xml`
  - Background colour: `#0D6273` (teal deep)
  - Foreground: `mipmap/ic_launcher_foreground` (per-DPI versions)
  - Monochrome: `ic_launcher_monochrome.xml` (orbit vector for themed icons)
  
- **Icon Foreground Variants**:
  - mdpi: `/Users/shawket/Desktop/madar-pos/kotlin-app/composeApp/src/androidMain/res/mipmap-mdpi/ic_launcher_foreground.png`
  - hdpi, xhdpi, xxhdpi, xxxhdpi: corresponding scaled versions
  
- **Monochrome SVG Vector**: `/Users/shawket/Desktop/madar-pos/kotlin-app/composeApp/src/androidMain/res/drawable/ic_launcher_monochrome.xml` (orbit + 2 dots)

**iOS (Swift)**:
- **App Icon Set**: `/Users/shawket/Desktop/madar-pos/swift-app/Resources/Assets.xcassets/AppIcon.appiconset/`
  - `AppIcon-1024.png` (1024x1024)
  - `AppIcon-1024-dark.png` (1024x1024, dark appearance)
  - `AppIcon-1024-tinted.png` (1024x1024, tinted variant)
  - Configured in Contents.json with appearances (luminosity: dark, tinted)

- **Launch Logo**: `/Users/shawket/Desktop/madar-pos/swift-app/Resources/Assets.xcassets/MadarLaunchLogo.imageset/`
  - `wordmark-light.png` (2048x2048)
  - `wordmark-dark.png` (2048x2048)
  - Reference: Info.plist UILaunchScreen → UIImageName: "MadarLaunchLogo"

### 5. AUDIO ASSETS

**Notification/Order Sound** (bundled in both natives):
- Kotlin: `/Users/shawket/Desktop/madar-pos/kotlin-app/composeApp/src/androidMain/res/raw/new_order.wav`
- Swift: `/Users/shawket/Desktop/madar-pos/swift-app/Resources/Sounds/new_order.wav`
- Old Flutter: `/Users/shawket/Desktop/sufrix_pos/assets/sounds/new_order.wav`

**Audio Format**: RIFF/WAVE, Microsoft PCM, 16-bit, mono, 44100 Hz

**Flutter Integration**: Place at `assets/sounds/new_order.wav` and reference via `just_audio` package (already in sufrix_pos pubspec.yaml) or `flutter_local_notifications` for system alerts.

### SUMMARY TABLE

| Asset Type | Best Source | File | Dimensions | Variants | Usage |
|---|---|---|---|---|---|
| **App Icon** | Downloads | icon-symbol-teal.png | 1600x1600 | ink/light/teal | Launcher icon |
| **Splash** | Downloads | lockup-latin.png | 1600x1530 | +reversed | Launch screen |
| **Rail Lockup** | Downloads | lockup-latin.png / -reversed | 1600x1530 | Light/Dark | In-app branding |
| **Symbol** | Downloads | symbol-primary.png | 1600x1600 | 6 variants | UI elements |
| **Wordmark** | Downloads | wordmark-primary.png | 1600x486 | 4 variants | Branding |
| **Fonts** | Kotlin/Swift/sufrix | Cairo-*.ttf (5 files) | N/A | 400-800 weight | Typography |
| **Menu Icons** | Kotlin/Swift | ic_*.xml / *.pdf | 24-48 dp | 100+ | UI buttons |
| **Order Sound** | Kotlin/Swift/sufrix | new_order.wav | N/A | Mono 44.1kHz | Alerts |

---

All file paths are absolute and ready for direct use. SVG versions of all logos available in `/Users/shawket/Downloads/Madar-Assets/svg/` for unlimited scaling.