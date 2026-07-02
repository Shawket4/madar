Perfect! Now I have all the design token files. Let me compile a comprehensive markdown report with exact values for your Flutter design_system package.

# Madar POS Kotlin Design Tokens - Exact Values for Flutter Design System

## 1. Color Roles (Light & Dark Themes)

### Light Theme (Navy palette - original)
| Role | Hex | ARGB |
|------|-----|------|
| **Background** | `#EFF3F4` | `0xFFEFF3F4` |
| **Surface** | `#FFFFFF` | `0xFFFFFFFF` |
| **Surface Alt** | `#E7EEEF` | `0xFFE7EEEF` |
| **Surface Raised** | `#FFFFFF` | `0xFFFFFFFF` |
| **Border** | `#D7E0E1` | `0xFFD7E0E1` |
| **Border Light** | `#E7EEEF` | `0xFFE7EEEF` |
| **Text Primary** | `#14181E` | `0xFF14181E` |
| **Text Secondary** | `#54636B` | `0xFF54636B` |
| **Text Muted** | `#76828B` | `0xFF76828B` |
| **Text On Accent** | `#FFFFFF` | `0xFFFFFFFF` |
| **Accent (Teal Deep)** | `#0D6273` | `0xFF0D6273` |
| **Accent BG** | `#DCE9EB` | `0xFFDCE9EB` |
| **Navy** | `#0D6273` | `0xFF0D6273` |
| **Navy BG** | `#DCE9EB` | `0xFFDCE9EB` |
| **Success** | `#16A34A` | `0xFF16A34A` |
| **Success BG** | `#E7F6EC` | `0xFFE7F6EC` |
| **Danger** | `#DC2626` | `0xFFDC2626` |
| **Danger BG** | `#FBEAEA` | `0xFFFBEAEA` |
| **Warning** | `#B45309` | `0xFFB45309` |
| **Warning BG** | `#F7ECDD` | `0xFFF7ECDD` |
| **Shadow (ink wash)** | `#14181E` @ 5.3% | `0x0D14181E` |

### Dark Theme (Brighter Teal identity - terracotta)
| Role | Hex | ARGB |
|------|-----|------|
| **Background** | `#14181E` | `0xFF14181E` |
| **Surface** | `#1B2128` | `0xFF1B2128` |
| **Surface Alt** | `#222A32` | `0xFF222A32` |
| **Surface Raised** | `#262F38` | `0xFF262F38` |
| **Border** | `#313B45` | `0xFF313B45` |
| **Border Light** | `#232C35` | `0xFF232C35` |
| **Text Primary** | `#EFF3F4` | `0xFFEFF3F4` |
| **Text Secondary** | `#AEB9C0` | `0xFFAEB9C0` |
| **Text Muted** | `#76828B` | `0xFF76828B` |
| **Text On Accent** | `#FFFFFF` | `0xFFFFFFFF` |
| **Accent (Teal Light)** | `#2E94A6` | `0xFF2E94A6` |
| **Accent BG** | `#123038` | `0xFF123038` |
| **Navy (Brighter)** | `#5FB6C7` | `0xFF5FB6C7` |
| **Navy BG** | `#15333B` | `0xFF15333B` |
| **Success** | `#3BCE7E` | `0xFF3BCE7E` |
| **Success BG** | `#13291D` | `0xFF13291D` |
| **Danger** | `#F4655A` | `0xFFF4655A` |
| **Danger BG** | `#33191B` | `0xFF33191B` |
| **Warning** | `#F0A23F` | `0xFFF0A23F` |
| **Warning BG** | `#332512` | `0xFF332512` |
| **Shadow (black)** | `#000000` @ 40% | `0x66000000` |

**Theme Color Naming:**
- Light theme uses ink (#14181E) on paper (#EFF3F4) with teal accent
- Dark theme uses paper on ink with brighter teal (#2E94A6)
- Both themes share success/warning/danger semantic colors but with different background tints
- Elevation uses ink shadow in light mode, pure black in dark mode (both via `Elevation` enum)

---

## 2. Spacing Scale, Corner Radii & Sizing

### Space (Dp values)
```
xs  = 4.dp
sm  = 8.dp
md  = 12.dp
lg  = 16.dp
xl  = 24.dp
xxl = 32.dp
```

### Radii (Corner radius values)
```
xs   = 8.dp
sm   = 12.dp
md   = 16.dp
lg   = 20.dp
xl   = 24.dp
xxl  = 32.dp
pill = 999.dp (fully rounded)
```

### Grid (Card layout system)
```
gutter       = 16.dp (Space.lg — gap between cards)
cellMax      = 208.dp (max card width)
padding      = 16.dp (Space.lg — outer grid padding)
```

### Icon Sizes (semantic scale)
```
xs  = 12.dp
sm  = 14.dp
md  = 16.dp (default)
lg  = 18.dp
xl  = 20.dp
xxl = 24.dp
```

### Named Component Metrics
```
buttonHeight     = 54.dp
inputHeight      = 48.dp
amountFieldHeight= 64.dp
tableHeaderHeight= 42.dp
tableRowHeight   = 56.dp
iconTile         = 38.dp
stepper          = 30.dp
ingredientBox    = 54.dp
closeButton      = 32.dp
pinKey           = 64.dp
```

### Semantic Opacity/Alpha
```
subtle   = 0.14f (faint tints, decorative rings)
border   = 0.25f (chip/banner hairline borders)
disabled = 0.45f (disabled controls)
scrim    = 0.45f (sheet/modal scrim overlay)
press    = 0.08f (press overlay)
```

### Responsive Breakpoints (BoxWithConstraints on container width)
```
tablet         = 600.dp  (≥ → tablet spacing/wider forms)
wideTable      = 680.dp  (≥ → table layout for history/shifts)
wide           = 760.dp  (≥ → split/side-by-side: login, open-shift, order)
desktop        = 1100.dp (≥ → desktop mode: cap & center content)

// Content max-widths (centering caps, never stretches)
formMaxWidth        = 520.dp
formMaxWidthWide    = 600.dp (≥ tablet)
listMaxWidth        = 560.dp
contentMaxWidth     = 880.dp
sheetMaxWidth       = 600.dp (ResponsiveSheet cap)
sheetCompactMaxWidth= 540.dp (item/bundle customize sheets)

// Split ratio
brandPanelRatio     = 0.55f (brand panel ↔ form split)
```

**Responsive form width logic:**
```
width >= 600.dp ? 600.dp : 520.dp
```

---

## 3. Typography

### Font Family
- **Cairo** (bundled in compose-resources/font)
  - Available weights: Regular, Medium, SemiBold, Bold, ExtraBold
  - All text uses Cairo via `LocalMadarFont` (no fallback to system font)

### Type Scale (all Cairo font family)
| Style | Size | Weight | Letter Spacing | Tabular? | Usage |
|-------|------|--------|-----------------|----------|-------|
| **display()** | 34.sp | ExtraBold | -0.5.sp | No | Hero numbers, grand totals |
| **h1()** | 30.sp | ExtraBold | -0.4.sp | No | Hero, screen titles |
| **h2()** | 22.sp | Bold | -0.2.sp | No | Section, sheet titles |
| **h3()** | 17.sp | SemiBold | Unspecified | No | Card titles |
| **title()** | 15.sp | SemiBold | Unspecified | No | Emphasized rows |
| **body()** | 14.sp | Medium | Unspecified | No | Default body text |
| **bodySm()** | 13.sp | Normal | Unspecified | No | Secondary body |
| **label()** | 12.sp | SemiBold | Unspecified | No | Uppercase labels |
| **labelSm()** | 11.sp | SemiBold | Unspecified | No | Chips, dense labels |
| **money()** | 14.sp | Bold | Unspecified | **YES** | Amount display (tabular figures "tnum") |
| **moneyLg()** | 24.sp | ExtraBold | Unspecified | **YES** | Large amounts |
| **moneyDisplay()** | 34.sp | ExtraBold | Unspecified | **YES** | Hero amount totals |

**Tabular Figures:** Money styles use `fontFeatureSettings = "tnum"` to enable monospaced digit rendering so amount columns line up vertically.

**Motion tracking (letter-spacing):**
```
trackingSp = 0.6f (sp) — used for uppercase label letter-spacing
```

---

## 4. Elevation Model (Shadows)

Elevation uses soft layered shadows via `Modifier.elevation(level: Elevation, shape: Shape)`. Shadow color is the Madar ink (#14181E) in light mode or black in dark mode.

| Level | Light Blur Radius | Dark Blur Radius | Ambient Color | Spot Color | Usage |
|-------|-------------------|------------------|---------------|-----------|-------|
| **NONE** | — | — | — | — | No shadow |
| **CARD** | 10.dp | 14.dp | Ink/Black | Ink/Black | Cards, low elevation |
| **RAISED** | 22.dp | 30.dp | Ink/Black | Ink/Black | Raised surfaces |
| **GLOW** | 18.dp | 18.dp | Accent color | Accent color | Highlighted/focus state |

**Shadow tint (Elevation.kt):**
```kotlin
private val InkShadow = Color(0xFF14181E)  // Madar ink
val base = if (isDark) Color.Black else InkShadow
// Applied to both ambientColor and spotColor
```

**Shadow configuration:**
- `clip = false` — shadow falls outside the shape (component applies own clip/background after)
- Shape parameter determines rounded/pill corners

---

## 5. Motion / Animation Specs

### Spring Animations (response/damping tuned to match SwiftUI)

| Spec | Function | Damping Ratio | Stiffness | Usage | Swift equivalent |
|------|----------|---------------|-----------|-------|------------------|
| **press** | `press()` | 0.72f | 620f | Buttons, chips, cards, tactile rebound | spring 0.22/0.7 |
| **sheet** | `sheet()` | 0.9f | 300f | Bottom-sheet, overlay slide | spring 0.34/0.9 |
| **bouncy** | `bouncy()` | Spring.DampingRatioMediumBouncy | 520f | PIN dots, qty steppers, badges | — |

### Tween Animations (eased, finite duration)

| Spec | Function | Duration | Easing | Usage |
|------|----------|----------|--------|-------|
| **standard** | `standard()` | 220 ms | EaseOut | Color, opacity, border, cross-fades |
| **gentle** | `gentle()` | 300 ms | EaseInOut | Route/tab swaps, slower content fades |

### Motion Constants
```kotlin
pressScale     = 0.97f   // Tactile press button scale
pressScaleKey  = 0.92f   // PIN key press scale (deeper)
trackingSp     = 0.6f    // Uppercase label letter-spacing (sp)
```

### Sheet Dismissal
- Slide-out animation: 280 ms duration (implicit via MotionSpec.sheet())
- `onDismiss` fires AFTER animation completes

### Skeleton Animation
```kotlin
Infinite repeating tween:
  duration: 900 ms
  mode: RepeatMode.Reverse
  animates alpha from 1f → 0.5f → 1f
```

---

## 6. RTL (Right-to-Left) Support

**File:** `Rtl.kt` provides direction-aware glyph helpers:

```kotlin
fun isRtlLayout(): Boolean  // True when LayoutDirection.Rtl is active

fun backGlyph(): String
  // "‹" in LTR (points toward leading edge)
  // "›" in RTL (leading edge is on right)

fun disclosureGlyph(): String
  // "›" in LTR (points toward trailing edge)
  // "‹" in RTL
```

**Icon Mirroring (Icons.kt):**
Directional glyphs flip in RTL via `iconMirror` mapping:
```kotlin
"chevron.right" ↔ "chevron.left"
"chevron.forward" ↔ "chevron.backward"
```

Compose auto-mirrors layout (Row, Start/End, padding) under LocalLayoutDirection.Rtl, but plain-text glyphs like "‹" / "›" are NOT mirrored — so these helpers pick the correct glyph.

---

## 7. Icons

### Icon Architecture
- **Dual-path system:** SF Symbol names (SwiftUI compatibility) → Material vectors OR Lucide drawables
- **Primary source:** Lucide vector graphics (shared asset set between Swift and Compose)
- **Fallback:** Material Design icons from `androidx.compose.material.icons`
- **Mirroring:** RTL-aware chevron flipping (see §6)

### MadarIcon Function
```kotlin
@Composable
fun MadarIcon(
    name: String?,           // SF Symbol name (e.g., "printer", "checkmark.circle")
    tint: Color,            // Icon color
    size: Dp = IconSize.md, // 16.dp default
    modifier: Modifier = Modifier
)
```

**Logic:**
1. Return early if name is null
2. If RTL, apply glyph mirror mapping
3. Look up Lucide drawable via `lucideRes(resolved)`
4. If Lucide exists, render via `Icon(painterResource(lucide), ...)`
5. Fall back to `sfSymbol(name)` Material vector
6. Return no-op if neither found

**SfIcon** is a legacy alias for MadarIcon (identical behavior).

### Full Icon Catalog (SF Symbol name → Lucide drawable)

**Navigation & Disclosure**
- `chevron.left` → `ic_chevron_left`
- `chevron.right` → `ic_chevron_right`
- `chevron.forward` → `ic_chevron_right`
- `chevron.backward` → `ic_chevron_left`
- `chevron.up` → `ic_chevron_up`
- `chevron.down` → `ic_chevron_down`
- `arrow.up` → `ic_chevron_up`
- `arrow.down` → `ic_chevron_down`
- `arrow.up.arrow.down` → `ic_arrow_up_down`
- `arrow.down.left` → `ic_arrow_down_left`
- `arrow.up.right` → `ic_arrow_up_right`
- `arrow.up.circle` → `ic_circle_arrow_up`
- `arrow.down.circle` → `ic_circle_arrow_down`
- `arrow.right.circle` → `ic_circle_arrow_right`

**Status & Feedback**
- `checkmark` → `ic_check`
- `checkmark.circle` → `ic_circle_check`
- `checkmark.circle.fill` → `ic_circle_check_big`
- `checkmark.seal` → `ic_badge_check`
- `checkmark.icloud` → `ic_cloud_check`
- `xmark` → `ic_x`
- `xmark.circle` → `ic_circle_x`
- `xmark.circle.fill` → `ic_circle_x`
- `exclamationmark.circle` → `ic_circle_alert`
- `exclamationmark.triangle` → `ic_triangle_alert`
- `exclamationmark.triangle.fill` → `ic_triangle_alert`
- `exclamationmark.bubble` → `ic_message_square_warning`

**User & Account**
- `person` → `ic_user`
- `person.fill` → `ic_user`
- `person.crop.circle.badge.clock` → `ic_circle_user`

**Communication & Messages**
- `text.bubble` → `ic_message_square`
- `envelope` → `ic_mail`
- `line.3.horizontal.decrease.circle` → `ic_list_filter`

**Search & Input**
- `magnifyingglass` → `ic_search`
- `qrcode` → `ic_qr_code`
- `qr` → `ic_qr_code`
- `lock` → `ic_lock`
- `lock.circle` → `ic_lock`
- `lock.open` → `ic_lock_open`
- `delete.left` → `ic_delete`

**Commerce & Shopping**
- `cart` → `ic_shopping_cart`
- `bag.fill` → `ic_shopping_bag`
- `creditcard` → `ic_credit_card`
- `wallet` → `ic_wallet`
- `banknote` → `ic_banknote`
- `receipt` → `ic_receipt`

**Business & Settings**
- `building.2` → `ic_building_2`
- `bank` → `ic_landmark`
- `building.columns` → `ic_landmark`
- `storefront` → `ic_store`
- `gearshape` → `ic_settings`
- `layers` → `ic_layers`
- `square.stack.3d.up.fill` → `ic_layers`
- `square.grid.2x2.fill` → `ic_grid_2x2`
- `square.grid.2x2` → `ic_grid_2x2`

**Time & Schedule**
- `clock` → `ic_clock`
- `clock.badge.checkmark` → `ic_clock`
- `clock.badge.exclamationmark` → `ic_clock`
- `clock.arrow.circlepath` → `ic_history`
- `history` → `ic_history`

**File & Document**
- `note.text` → `ic_file_text`
- `doc.text` → `ic_file_text`
- `printer` → `ic_printer`
- `trash` → `ic_trash_2`
- `trash.fill` → `ic_trash_2`

**Upload & Cloud**
- `icloud.and.arrow.up` → `ic_cloud_upload`
- `tray.and.arrow.down` → `ic_download`
- `tray.full` → `ic_inbox`
- `tray` → `ic_inbox`
- `rectangle.portrait.and.arrow.right` → `ic_log_out`

**Semantic & Misc**
- `plus` → `ic_plus`
- `minus` → `ic_minus`
- `plus.forwardslash.minus` → `ic_calculator`
- `list.bullet.rectangle` → `ic_list`
- `list.bullet` → `ic_list`
- `hand.raised` → `ic_hand`
- `heart.circle` → `ic_heart`
- `wifi` → `ic_wifi`
- `wifi.slash` → `ic_wifi_off`
- `bicycle` → `ic_bike`

**Display & Visualization**
- `circle` → `ic_circle`
- `largecircle.fill.circle` → `ic_circle_dot`
- `rectangle.split.2x1` → `ic_columns_2`
- `ellipsis.circle` → `ic_ellipsis`
- `ellipsis` → `ic_ellipsis`
- `tag` → `ic_tag`
- `tag.fill` → `ic_tag`
- `number` → `ic_hash`
- `play.circle` → `ic_circle_play`
- `chart.pie` → `ic_pie_chart`
- `link` → `ic_link`
- `slider.horizontal.3` → `ic_sliders_horizontal`

**Refresh & Sync**
- `arrow.triangle.2.circlepath` → `ic_refresh_cw`
- `arrow.clockwise` → `ic_rotate_cw`

**Food/Beverage Category Icons** (catalog-specific, map to food assets)
- `cat.coffee` → `ic_coffee`
- `cat.mocha` → `ic_coffee`
- `cat.tea` → `ic_coffee`
- `cat.bakery` → `ic_croissant`
- `cat.lunch` → `ic_sandwich`
- `cat.icecream` → `ic_ice_cream_cone`
- `cat.drink` → `ic_cup_soda`
- `cat.water` → `ic_glass_water`
- `cat.ice` → `ic_snowflake`
- `cat.matcha` → `ic_leaf`

**Additional**
- `iphone` → `ic_smartphone`
- `line.3.horizontal` → `ic_menu`
- `shippingbox` → `ic_package`
- `star` → `ic_star`
- `gift` → `ic_gift`

---

## 8. Skeleton (Loading State)

**File:** `Skeleton.kt` — shimmer implementation for list loading states.

### SkeletonBlock (base shimmer unit)
```kotlin
@Composable
fun SkeletonBlock(
    width: Dp? = null,
    height: Dp = 13.dp,
    corner: Dp = 6.dp,
    modifier: Modifier = Modifier
)
```
- **Shape:** Rounded rectangle with configurable corner radius
- **Color:** `surfaceAlt` (light: #E7EEEF, dark: #222A32)
- **Animation:** Infinite repeating tween
  - Duration: 900 ms
  - Mode: RepeatMode.Reverse
  - Animates alpha: 1f → 0.5f → 1f

### SkeletonRow (card-shaped placeholder)
```kotlin
@Composable
fun SkeletonRow()
```
- **Layout:** Row inside a card (rounded border + padding)
- **Shape:** RoundedCornerShape(Radii.sm) = 12.dp corners
- **Background:** `surface` color
- **Border:** 1.dp, `border` color
- **Padding:** Space.md (12.dp)
- **Content:**
  - Left column: Two stacked SkeletonBlocks (130.dp×14.dp, 80.dp×11.dp) with 8.dp gap
  - Right side: Single SkeletonBlock (56.dp×14.dp)
  - Horizontal spacing: Space.md (12.dp)

### SkeletonList (collection)
```kotlin
@Composable
fun SkeletonList(count: Int = 6)
```
- **Layout:** Column of [count] SkeletonRow items
- **Max width:** 560.dp (Responsive.listMaxWidth)
- **Vertical spacing:** Space.sm (8.dp)
- **Padding:** Space.lg (16.dp)

---

## 9. Haptics (Tactile Feedback)

**File:** `Haptics.kt` — centralized haptic events (Compose 1.7 maps to two types).

### Haptics Class Methods
All fire via `HapticFeedback.performHapticFeedback(HapticFeedbackType)`.

| Method | HapticFeedbackType | Usage |
|--------|-------------------|-------|
| `selection()` | TextHandleMove | Light tick: chips, toggles, PIN keys, selection changes |
| `impact()` | LongPress | Medium thud: primary actions (add to cart, place order, confirm) |
| `success()` | LongPress | Positive confirmation: order placed, shift opened, sale finalized |
| `warning()` | LongPress | Error nudge: failed validation, blocked action, max reached |

### Usage Pattern
```kotlin
@Composable
fun MyScreen() {
    val haptics = rememberHaptics()
    Button(onClick = { haptics.selection() }) { ... }
}
```

**No-op on desktop** (no haptic hardware; LocalHapticFeedback ignores calls).

---

## 10. Toast

**File:** `Toast.kt` — transient bottom banner with optional action.

### ToastData
```kotlin
data class ToastData(
    val id: Int,              // Unique identifier
    val text: String,         // Message text
    val tone: ChipTone = ChipTone.NEUTRAL,  // Color/semantic tone
    val actionLabel: String? = null,        // Optional action button text
    val seconds: Double = 2.6,              // Auto-dismiss duration
    val icon: String? = null                // Optional SF Symbol name
)
```

### ToastHost Composable
```kotlin
@Composable
fun ToastHost(
    toast: ToastData?,
    onAction: () -> Unit,
    onDismiss: (Int) -> Unit
)
```

**Anatomy:**
- **Layout:** Aligned to BottomCenter inside a fillMaxSize Box
- **Shape:** RoundedCornerShape(999.dp) = pill
- **Background:** `surfaceRaised`
- **Border:** 1.dp, `border` color
- **Padding:** 
  - Horizontal: Space.lg (16.dp)
  - Vertical: Space.md (12.dp)
  - Bottom offset from screen: 40.dp
  - Max width: 460.dp
- **Content spacing:** Space.sm (8.dp)

**Text Styling:**
- **Message:** Cairo SemiBold, 13.sp, `textPrimary` color
- **Action button:** Cairo Black (FontWeight.Black), 13.sp, accent color, clickable
- **Icon:** 16.dp size (SfIcon), accent-colored tint

**Tone Color Mapping:**
| Tone | Color |
|------|-------|
| INFO | `navy` |
| ACCENT | `accent` |
| SUCCESS | `success` |
| WARNING | `warning` |
| DANGER | `danger` |
| NEUTRAL | `textSecondary` |

**Animation:**
- **Enter:** fadeIn() + slideInVertically (from 50% offset)
- **Exit:** fadeOut() + slideOutVertically (to 50% offset)
- **Auto-dismiss:** Fires onDismiss after `toast.seconds * 1000` milliseconds
- **Persistence:** Keeps last shown payload during exit animation (no hard cut)

---

## 11. MadarSheet (Bottom Modal)

**File:** `MadarSheet.kt` — shared modal presenter for all sheets.

### SheetSize Enum
| Size | Height Cap | Use Case |
|------|------------|----------|
| **AUTO** | 88% of container | Default for medium sheets |
| **LARGE** | 94% of container | Big sheets (checkout, tender) |
| **HUG** | 92% of container (scrolls only on overflow) | Item/bundle customize sheets (must not stretch empty void) |

### MadarSheet Signature
```kotlin
@Composable
fun MadarSheet(
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
    size: SheetSize = SheetSize.AUTO,
    maxWidth: Dp = Responsive.sheetMaxWidth,  // 600.dp
    content: @Composable ColumnScope.(dismiss: () -> Unit) -> Unit
)
```

### Sheet Anatomy

**Card:**
- **Shape:** RoundedCornerShape(topStart = Radii.xl, topEnd = Radii.xl) = 24.dp corners
- **Background:** `surface`
- **Border:** 1.dp, `borderLight` color
- **Elevation:** RAISED (22.dp light / 30.dp dark blur shadow)
- **Max width:** 600.dp (Responsive.sheetMaxWidth)
- **Responsive:** Caps at 540.dp for compact sheets

**Drag Handle:**
- **Shape:** CircleShape (pill)
- **Size:** 40.dp × 5.dp
- **Color:** `border`
- **Padding:** top Space.md (12.dp), bottom Space.sm (8.dp)
- **Interaction:** Drag down > 28% of maxHeight → dismiss; otherwise snap back

**Scrim:**
- **Color:** Color.Black
- **Alpha:** Opacity.scrim (0.45f) when shown, 0f when hidden
- **Gesture:** Tap scrim → dismiss
- **Animation:** MotionSpec.standard() (220 ms EaseOut)

### Sheet Animation

| Phase | Animation | Duration | Spec |
|-------|-----------|----------|------|
| **Slide in** | Translates from bottom (hiddenPx offset) to 0 | Spring (damp 0.9, stiff 300) | MotionSpec.sheet() |
| **Scrim fade** | Alpha 0 → 0.45 | 220 ms EaseOut | MotionSpec.standard() |
| **Drag** | Live user drag offset (Animatable) | Instantaneous | User input |
| **Snap back** | If drag < 28% threshold, animate back to 0 | Spring (sheet spec) | MotionSpec.sheet() |
| **Dismiss slide** | Translates down to hiddenPx | Spring (sheet spec) | MotionSpec.sheet() |
| **Dismiss scrim** | Alpha 0.45 → 0 | 220 ms EaseOut | MotionSpec.standard() |
| **Post-dismiss callback** | onDismiss fires | +280 ms after slide out starts | Explicit delay |

**Key detail:** onDismiss is delayed 280 ms to fire AFTER slide-out completes, so the caller's boolean binding only flips once the card is off-screen (no hard cut).

**Drag dismissal threshold:** 28% of maxHeight

---

## Summary: Design Token Layers for Flutter

1. **Colors** – 19 named roles × 2 themes (light/dark) with exact hex/ARGB
2. **Spacing** – 6-level scale (4–32 dp) plus semantic component metrics
3. **Radii** – 6-level scale (8–32 dp) plus pill (999 dp)
4. **Typography** – Cairo family, 9 semantic styles, tabular figures for money
5. **Elevation** – 4 levels (NONE/CARD/RAISED/GLOW) with light/dark shadow tints
6. **Motion** – 3 springs + 2 tweens, all parameters exact (ms durations, damping, stiffness)
7. **RTL** – Glyph flipping for chevrons, auto-mirroring on LayoutDirection.Rtl
8. **Icons** – 100+ SF Symbol → Lucide/Material mappings, RTL-aware
9. **Skeleton** – Infinite alpha pulse (900 ms reverse), card/row/list presets
10. **Haptics** – 4 semantic events (selection/impact/success/warning) via TextHandleMove + LongPress
11. **Toast** – Pill shape, 6 tones, auto-dismiss (2.6 s default), fade + slide animation
12. **Sheet** – Spring-driven slide in/out, 3 size modes, drag-to-dismiss (>28% threshold), scrim interaction

All values are design-token constants: no hardcoded pixel values in components, RTL-aware layout, accessible opacity scales, and animation parity with SwiftUI.