//! Receipt → 1-bit raster bitmap.
//!
//! The TSP143III is raster-only and receipts carry an org logo + Arabic, so the
//! whole receipt is rendered to an image here (not text commands) and shipped via
//! the raster wrappers in [`crate::receipt`]. The layout mirrors the on-screen
//! `ReceiptPaper` preview (centered logo → uppercase store name → rules →
//! two-column money rows → indented modifiers → centered footer) so the teller
//! prints exactly what they saw. Text is shaped with the embedded Cairo font
//! (Arabic shaping + bidi via cosmic-text), the same font the app UI uses.
//!
//! Output is deterministic for a given input + font, so all three hosts print a
//! byte-identical receipt. Ink is rendered solid black: the preview's gray
//! "faint" text would threshold to white on a 1-bit head, so hierarchy is carried
//! by weight/size/indentation exactly as the preview does structurally.

use cosmic_text::{Attrs, Buffer, Color, Family, FontSystem, Metrics, Shaping, SwashCache, Weight};

use crate::checkout::{ReceiptLineView, ReceiptModifierView, ReceiptView};
use crate::receipt::{money, short_id, Bitmap, EscPosCtx, KitchenChitLabels, KitchenSlip, TillReportLabels};
#[cfg(test)]
use crate::receipt::KitchenSlipItem;
use crate::till::TillReportView;

/// Printable width in dots — 72 mm @ 203 dpi. Matches the Flutter `_printerWidth`
/// and the Star raster row width (576 / 8 = 72 bytes).
pub const PRINT_WIDTH: u32 = 576;

const MARGIN: i32 = 16; // left/right quiet zone, dots
const TOP_PAD: i32 = 16;
const BOTTOM_PAD: i32 = 28; // trailing whitespace before the cut

const LINE: f32 = 1.30; // line-height multiple

// Font sizes (dots), tuned to the preview's sp ratios scaled to 576 px —
// shared by the receipt, the kitchen slip and the till report, so all three
// read at the same bold, larger weight.
const RS_ORDER: f32 = 64.0;
const RS_TOTAL: f32 = 38.0;
const RS_BODY: f32 = 29.0;
const RS_SMALL: f32 = 26.0;

// Org-logo bounding box (dots) — 50% over the old 352×96. Fit-inside and
// aspect-preserved after blank borders are trimmed; a small logo scales UP to
// the box (see `decode_logo`), so a wide wordmark, a square mark, a tiny
// upload and a logo padded with whitespace all print at a sensible size.
const LOGO_MAX_W: u32 = 792;
const LOGO_MAX_H: u32 = 216;

// Branch name under the hairline — smaller than the old above-hairline size.
const RS_BRANCH: f32 = 30.0;

// Embedded Cairo — the same family the Compose/Swift UI renders. Regular for
// body, SemiBold for the payment label, Bold for headers/totals.
const CAIRO_REGULAR: &[u8] = include_bytes!("../assets/fonts/Cairo-Regular.ttf");
const CAIRO_SEMIBOLD: &[u8] = include_bytes!("../assets/fonts/Cairo-SemiBold.ttf");
const CAIRO_BOLD: &[u8] = include_bytes!("../assets/fonts/Cairo-Bold.ttf");

/// Render the receipt to a 1-bit bitmap. `logo` is the decoded org-logo image
/// bytes the core fetched + cached, or `None` to print without it.
pub fn render_receipt(
    receipt: &ReceiptView,
    ctx: &EscPosCtx,
    logo: Option<&[u8]>,
    width: u32,
) -> Bitmap {
    let mut r = Renderer::new(width);
    r.build(receipt, ctx, logo);
    r.canvas.into_bitmap()
}

/// Render the shift report (Z-report) to a 1-bit bitmap — same engine/look as the
/// receipt, mirroring the on-screen `ShiftReportBreakdown` preview. `orders` is
/// the per-order breakdown appended when the teller prints the EXPANDED report
/// (empty = summary only, the default).
pub fn render_till_report(
    report: &TillReportView,
    store: &str,
    currency: &str,
    labels: &TillReportLabels,
    orders: &[crate::orders::OrderSummaryView],
    width: u32,
) -> Bitmap {
    let mut r = Renderer::new(width);
    r.build_till(report, store, currency, labels, orders);
    r.canvas.into_bitmap()
}

/// Render a kitchen slip to a 1-bit bitmap — the SAME font + shaping engine
/// as a receipt (Arabic/RTL included), so a kitchen chit never garbles a
/// non-Latin item name or note the way the old raw-UTF-8 text encoder did.
/// No logo, no money, no footer — just the header, the notes that apply to
/// the whole slip once, and every item with only its own note.
pub fn render_kitchen_chit(slip: &KitchenSlip, labels: &KitchenChitLabels, width: u32) -> Bitmap {
    let mut r = Renderer::new(width);
    r.build_kitchen_slip(slip, labels);
    r.canvas.into_bitmap()
}

// ── grayscale canvas ─────────────────────────────────────────────────────────

/// A growable single-channel coverage canvas: one byte per dot, 0 = blank,
/// 255 = full ink. Height grows as content is appended.
struct Canvas {
    w: usize,
    px: Vec<u8>,
}

impl Canvas {
    fn new(w: usize) -> Self {
        Canvas { w, px: Vec::new() }
    }

    fn height(&self) -> usize {
        self.px.len() / self.w
    }

    /// Ensure the canvas is at least `rows` tall.
    fn grow_to(&mut self, rows: usize) {
        if rows > self.height() {
            self.px.resize(rows * self.w, 0);
        }
    }

    /// Max-blend coverage at (x, y); out-of-bounds is dropped, height grows down.
    fn cover(&mut self, x: i32, y: i32, a: u8) {
        if a == 0 || x < 0 || y < 0 || x as usize >= self.w {
            return;
        }
        let (x, y) = (x as usize, y as usize);
        self.grow_to(y + 1);
        let i = y * self.w + x;
        if a > self.px[i] {
            self.px[i] = a;
        }
    }

    /// A solid horizontal rule from `x0`..`x1` at `y`, `thick` dots tall.
    fn rule(&mut self, x0: i32, x1: i32, y: i32, thick: i32) {
        for dy in 0..thick {
            for x in x0..x1 {
                self.cover(x, y + dy, 255);
            }
        }
    }

    /// Threshold the coverage canvas to a packed 1-bit MSB-first bitmap.
    fn into_bitmap(self) -> Bitmap {
        let rows = self.height() as u32;
        let wb = (self.w + 7) / 8;
        let mut bytes = vec![0u8; wb * self.height()];
        for y in 0..self.height() {
            for x in 0..self.w {
                if self.px[y * self.w + x] >= 128 {
                    bytes[y * wb + (x >> 3)] |= 0x80 >> (x & 7);
                }
            }
        }
        Bitmap {
            width: self.w as u32,
            rows,
            bytes,
        }
    }
}

// ── renderer ─────────────────────────────────────────────────────────────────

struct Renderer {
    fonts: FontSystem,
    cache: SwashCache,
    canvas: Canvas,
    y: i32, // current baseline cursor (top of the next block)
    // Paper geometry. The module constants above are tuned for `PRINT_WIDTH`
    // (576 dots / 72 mm); on a narrower roll (e.g. 384 dots / 58 mm) everything
    // — fonts, margins, logo box — scales down by `scale` so the layout is a
    // faithful miniature and never collides or overflows the head.
    width: i32,
    scale: f32,
    margin: i32,
    bottom_pad: i32,
    logo_w: u32,
    logo_h: u32,
    /// Every string shaped, in order — lets tests read what was printed.
    #[cfg(test)]
    shaped: Vec<String>,
    /// Every blit's text and its unclipped ink box `(x0, y0, x1, y1)` (end
    /// exclusive) — lets tests check where the ink landed, off-paper included.
    #[cfg(test)]
    inked: Vec<(String, (i32, i32, i32, i32))>,
    /// The strings drawn centred (`center` / `boxed`), each with the index
    /// of its blit in `inked`.
    #[cfg(test)]
    centered: Vec<(String, usize)>,
}

impl Renderer {
    fn new(width: u32) -> Self {
        // Guard against absurd/zero widths (would divide-by-zero the canvas).
        let width = width.clamp(64, 4096);
        let scale = width as f32 / PRINT_WIDTH as f32;
        let sc = |v: i32| (v as f32 * scale).round() as i32;
        let mut db = cosmic_text::fontdb::Database::new();
        db.load_font_data(CAIRO_REGULAR.to_vec());
        db.load_font_data(CAIRO_SEMIBOLD.to_vec());
        db.load_font_data(CAIRO_BOLD.to_vec());
        // Custom db only — never scan system fonts, so output is deterministic
        // and the Android/iOS sandboxes don't matter.
        let fonts = FontSystem::new_with_locale_and_db("en-US".to_string(), db);
        Renderer {
            fonts,
            cache: SwashCache::new(),
            canvas: Canvas::new(width as usize),
            y: sc(TOP_PAD),
            width: width as i32,
            scale,
            margin: sc(MARGIN),
            bottom_pad: sc(BOTTOM_PAD),
            logo_w: (LOGO_MAX_W as f32 * scale).round() as u32,
            logo_h: (LOGO_MAX_H as f32 * scale).round() as u32,
            #[cfg(test)]
            shaped: Vec::new(),
            #[cfg(test)]
            inked: Vec::new(),
            #[cfg(test)]
            centered: Vec::new(),
        }
    }

    /// Scale a `PRINT_WIDTH`-tuned dot measure (margin gaps, indents) to this roll.
    fn sx(&self, v: i32) -> i32 {
        (v as f32 * self.scale).round() as i32
    }

    fn content_w(&self) -> i32 {
        self.width - 2 * self.margin
    }

    /// Shape one string into a laid-out buffer at the given size/weight, wrapping
    /// at `max_w` dots.
    fn shape(&mut self, text: &str, size: f32, weight: Weight, max_w: i32) -> Buffer {
        #[cfg(test)]
        self.shaped.push(text.to_string());
        // Fonts are tuned for PRINT_WIDTH; scale to the active roll. `max_w` is
        // already in real (scaled) dots, so wrapping stays proportional.
        let size = size * self.scale;
        let mut buf = Buffer::new(&mut self.fonts, Metrics::new(size, size * LINE));
        // cosmic-text 0.19: set_size/set_text no longer take the FontSystem
        // (shaping is deferred to shape_until_scroll); attrs pass by ref.
        buf.set_size(Some(max_w as f32), None);
        let attrs = Attrs::new().family(Family::Name("Cairo")).weight(weight);
        buf.set_text(text, &attrs, Shaping::Advanced, None);
        buf.shape_until_scroll(&mut self.fonts, false);
        buf
    }

    /// Width (max run width) and height (bottom of last run) of a shaped buffer.
    fn measure(buf: &Buffer) -> (f32, f32) {
        let mut w = 0.0f32;
        let mut h = 0.0f32;
        for run in buf.layout_runs() {
            w = w.max(run.line_w);
            h = h.max(run.line_top + run.line_height);
        }
        (w, h)
    }

    /// How far a shaped buffer's ink starts from its left edge, in dots.
    /// cosmic-text lays an RTL (Arabic) paragraph out right-aligned inside
    /// the width it was shaped at, so its glyphs start at `max_w - line_w`,
    /// not at 0 as an LTR one's do. Whoever places a buffer by its measured
    /// width (centred, flush-right) subtracts this, or an Arabic line lands
    /// that far to the right, off the paper (B9). Always 0 for LTR text, so
    /// English prints exactly as before.
    fn rtl_lead(buf: &Buffer) -> i32 {
        buf.layout_runs()
            .filter(|run| run.rtl)
            .flat_map(|run| run.glyphs.iter())
            .map(|g| g.x)
            .reduce(f32::min)
            .map_or(0, |x| x.round() as i32)
    }

    /// Blit a shaped buffer with its left edge at `ox` and top at `oy`.
    fn blit(&mut self, buf: &Buffer, ox: i32, oy: i32) {
        let ink = Color::rgb(0, 0, 0);
        #[cfg(test)]
        let mut bx = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
        for run in buf.layout_runs() {
            let base_y = oy + run.line_y as i32;
            for glyph in run.glyphs.iter() {
                let phys = glyph.physical((0.0, 0.0), 1.0);
                let gx = ox + phys.x;
                let gy = base_y + phys.y;
                self.cache
                    .with_pixels(&mut self.fonts, phys.cache_key, ink, |dx, dy, color| {
                        #[cfg(test)]
                        if color.a() >= 128 {
                            let (x, y) = (gx + dx, gy + dy);
                            bx = (bx.0.min(x), bx.1.min(y), bx.2.max(x + 1), bx.3.max(y + 1));
                        }
                        self.canvas.cover(gx + dx, gy + dy, color.a());
                    });
            }
        }
        #[cfg(test)]
        {
            let text: Vec<&str> = buf.lines.iter().map(|l| l.text()).collect();
            self.inked.push((text.join("\n"), bx));
        }
    }

    /// Draw a centered text block at the current cursor, advancing past it.
    fn center(&mut self, s: &str, size: f32, weight: Weight) {
        if s.is_empty() {
            return;
        }
        let buf = self.shape(s, size, weight, self.content_w());
        let (w, h) = Self::measure(&buf);
        let ox = ((self.width as f32 - w) / 2.0).round() as i32 - Self::rtl_lead(&buf);
        let oy = self.y;
        #[cfg(test)]
        self.centered.push((s.to_string(), self.inked.len()));
        self.blit(&buf, ox, oy);
        self.y += h.ceil() as i32;
    }

    /// A two-column row: `left` flush-left, `right` flush-right on one baseline.
    fn row(&mut self, left: &str, right: &str, size: f32, weight: Weight) {
        let right_buf = self.shape(right, size, weight, self.content_w());
        let (rw, rh) = Self::measure(&right_buf);
        // Keep the label clear of the value.
        let left_max =
            (self.content_w() as f32 - rw - self.sx(12) as f32).max(self.sx(40) as f32) as i32;
        let left_buf = self.shape(left, size, weight, left_max);
        let (_, lh) = Self::measure(&left_buf);
        let oy = self.y;
        self.blit(&left_buf, self.margin, oy);
        if !right.is_empty() {
            let rx = self.width - self.margin - rw.round() as i32 - Self::rtl_lead(&right_buf);
            self.blit(&right_buf, rx, oy);
        }
        self.y += lh.max(rh).ceil() as i32;
    }

    /// A left-aligned line indented by `indent` dots (modifiers / address).
    fn indented(&mut self, s: &str, size: f32, indent: i32) {
        self.indented_w(s, size, Weight::NORMAL, indent);
    }

    fn indented_w(&mut self, s: &str, size: f32, weight: Weight, indent: i32) {
        let indent = self.sx(indent);
        let buf = self.shape(s, size, weight, self.content_w() - indent);
        let (_, h) = Self::measure(&buf);
        let oy = self.y;
        self.blit(&buf, self.margin + indent, oy);
        self.y += h.ceil() as i32;
    }

    fn rule(&mut self) {
        self.y += self.sx(4);
        self.canvas
            .rule(self.margin, self.width - self.margin, self.y, 2);
        self.y += self.sx(8);
    }

    fn gap(&mut self, dots: i32) {
        self.y += dots;
    }

    /// Centered text inside a drawn box — the order number.
    fn boxed(&mut self, s: &str, size: f32) {
        let buf = self.shape(s, size, Weight::BOLD, self.content_w() - self.sx(48));
        let (w, h) = Self::measure(&buf);
        let (pad_x, pad_y, t) = (self.sx(28), self.sx(6), self.sx(4).max(3));
        let bw = (w.ceil() as i32 + pad_x * 2).min(self.content_w());
        let bh = h.ceil() as i32 + pad_y * 2;
        let x0 = (self.width - bw) / 2;
        let y0 = self.y;
        self.canvas.rule(x0, x0 + bw, y0, t);
        self.canvas.rule(x0, x0 + bw, y0 + bh - t, t);
        for y in y0..y0 + bh {
            for x in 0..t {
                self.canvas.cover(x0 + x, y, 255);
                self.canvas.cover(x0 + bw - 1 - x, y, 255);
            }
        }
        let ox = ((self.width as f32 - w) / 2.0).round() as i32 - Self::rtl_lead(&buf);
        #[cfg(test)]
        self.centered.push((s.to_string(), self.inked.len()));
        self.blit(&buf, ox, y0 + pad_y);
        self.y += bh;
    }

    /// Decode, scale-to-fit and threshold the org logo to solid black, then composite it centered.
    fn logo(&mut self, bytes: &[u8]) {
        let Some((w, h, ink)) = decode_logo(bytes, self.logo_w, self.logo_h) else {
            return;
        };
        let ox = ((self.width - w as i32) / 2).max(0);
        let oy = self.y;
        for ly in 0..h {
            for lx in 0..w {
                if ink[ly * w + lx] != 0 {
                    self.canvas.cover(ox + lx as i32, oy + ly as i32, 255);
                }
            }
        }
        self.y += h as i32 + self.sx(8);
    }

    /// Walk the receipt top-to-bottom, mirroring `ReceiptPaper.kt`.
    fn build(&mut self, r: &ReceiptView, ctx: &EscPosCtx, logo: Option<&[u8]>) {
        let cur = &ctx.currency;
        let lab = &ctx.labels;
        let m = |minor: i64| money(minor, cur);

        // ── header ── logo sits directly above the hairline; the branch
        // name (smaller) goes directly below it.
        if r.is_voided {
            self.center(&format!("*** {} ***", lab.voided), RS_BODY, Weight::BOLD);
        }
        if let Some(bytes) = logo {
            self.logo(bytes);
        }
        self.rule();
        let store = if ctx.store_name.trim().is_empty() {
            "MADAR".to_string()
        } else {
            ctx.store_name.to_uppercase()
        };
        self.center(&store, RS_BRANCH, Weight::BOLD);
        if r.is_delivery {
            if let Some(ch) = r.delivery_channel.as_deref() {
                let label = if ch == "in_mall" {
                    &lab.channel_in_mall
                } else {
                    &lab.delivery
                };
                self.center(
                    &format!("— {} —", label.to_uppercase()),
                    RS_SMALL,
                    Weight::BOLD,
                );
            }
        }
        self.rule();

        // ── order meta ── the number boxed, big and centered; time under it.
        let number = match r.order_number {
            _ if !r.display_number.is_empty() => format!("#{}", r.display_number),
            Some(n) => format!("#{}", n),
            None => short_id(&r.local_order_id).to_string(),
        };
        self.gap(self.sx(4));
        self.center(&lab.order.to_uppercase(), RS_SMALL, Weight::BOLD);
        self.boxed(&number, RS_ORDER);
        self.gap(self.sx(6));
        self.center(&fmt_dt(lab, &r.created_at), RS_SMALL, Weight::BOLD);
        if let Some(rf) = &r.order_ref {
            // The label carries its own colon ("Ref:", "مرجع:").
            self.center(&format!("{} {}", lab.reference, rf), RS_SMALL, Weight::BOLD);
        }
        self.rule();

        // ── delivery block ──
        if r.is_delivery {
            if let Some(v) = &r.customer_name {
                self.row(&lab.customer, v, RS_SMALL, Weight::BOLD);
            }
            if let Some(v) = &r.customer_phone {
                self.row(&lab.phone, v, RS_SMALL, Weight::BOLD);
            }
            if let Some(v) = &r.delivery_address {
                self.indented(&format!("{}: {}", lab.address, v), RS_SMALL, 0);
            }
            if let Some(v) = &r.delivery_zone {
                self.row(&lab.zone, v, RS_SMALL, Weight::BOLD);
            }
            // Courier ref + COD/payment hint + customer instructions — the ESC/POS
            // text path printed these but the raster path (this) dropped them, so a
            // courier ticket lacked the ref/hint/notes the dispatcher needs.
            if let Some(v) = &r.delivery_ref {
                self.row(&lab.delivery_ref, v, RS_SMALL, Weight::BOLD);
            }
            if let Some(v) = &r.payment_hint {
                self.row(&lab.payment_hint, v, RS_SMALL, Weight::BOLD);
            }
            if let Some(v) = &r.delivery_notes {
                self.indented(&format!("{}: {}", lab.notes, v), RS_SMALL, 0);
            }
            self.rule();
        }

        // ── items ──
        for line in &r.lines {
            if line.kind == crate::menu::KIND_COMBO {
                self.combo_item(line, cur);
            } else {
                self.item(line, cur);
            }
        }
        self.rule();

        // ── totals ──
        // The lines at their normal prices; each deal then comes off under
        // it as its own row (C8), so the paper adds up.
        self.row(&lab.subtotal, &m(r.gross_subtotal_minor()), RS_BODY, Weight::BOLD);
        for d in &r.deals {
            self.row(&d.name, &format!("−{}", m(d.discount_minor)), RS_BODY, Weight::BOLD);
        }
        if r.discount_minor > 0 {
            self.row(
                &lab.discount,
                &format!("−{}", m(r.discount_minor)),
                RS_BODY,
                Weight::BOLD,
            );
        }
        // Before the tax, in the order the money is added: the service charge
        // (its own line, as on the paper and the screen) — the raster receipt
        // used to leave it out, so a table's printed lines did not add up.
        if r.service_charge_minor > 0 {
            self.row(
                &lab.service_charge,
                &m(r.service_charge_minor),
                RS_BODY,
                Weight::BOLD,
            );
        }
        // Always stated, and "included" when it is inside the prices.
        self.row(
            if r.tax_inclusive { &lab.vat_included } else { &lab.tax },
            &m(r.tax_minor),
            RS_BODY,
            Weight::BOLD,
        );
        if r.delivery_fee_minor > 0 {
            self.row(
                &lab.delivery_fee,
                &m(r.delivery_fee_minor),
                RS_BODY,
                Weight::BOLD,
            );
        }
        self.row(
            &lab.total.to_uppercase(),
            &m(r.total_minor),
            RS_TOTAL,
            Weight::BOLD,
        );
        if r.tax_inclusive {
            self.indented(&lab.prices_include_vat, RS_SMALL, 0);
        }
        if r.service_charge_waived_minor > 0 {
            self.row(
                &lab.service_waived,
                &format!("−{}", m(r.service_charge_waived_minor)),
                RS_SMALL,
                Weight::NORMAL,
            );
            if let Some(name) = r.service_charge_waived_by_name.as_deref() {
                self.indented(name, RS_SMALL, 0);
            }
        }
        if r.tip_minor > 0 {
            self.row(&lab.tip, &m(r.tip_minor), RS_BODY, Weight::BOLD);
        }
        if !r.payments.is_empty() {
            // A split prints what each method paid. It has no one "cash
            // tendered" figure, so the Cash/Change pair would read 0.00.
            for leg in &r.payments {
                self.row(&leg.label, &m(leg.amount_minor), RS_BODY, Weight::BOLD);
            }
        } else if r.is_cash {
            self.row(
                &lab.cash,
                &m(r.amount_tendered_minor),
                RS_BODY,
                Weight::BOLD,
            );
            self.row(&lab.change, &m(r.change_minor), RS_BODY, Weight::BOLD);
        }
        self.rule();

        // ── footer ── the payment method, then ONLY the org's own footer
        // (dashboard) or the default thank-you. No teller, no sync notice.
        self.center(&r.payment_label.to_uppercase(), RS_BODY, Weight::BOLD);
        self.gap(self.sx(6));
        self.center(&lab.thank_you, RS_BODY, Weight::BOLD);
        self.gap(self.bottom_pad);
    }

    /// Walk the Z-report top-to-bottom — the full detailed layout, mirroring the
    /// Flutter `_buildShiftReportPdf`: header (title, business date, print/close
    /// time — no branch name or logo, unlike the receipt) → shift info (teller,
    /// opened, closed / interim) → PAYMENTS (per
    /// method + order count, total collected, transactions) → DRAWER OPERATIONS
    /// (pay-in/out + itemised movements with times) → CASH RECONCILIATION
    /// (opening, expected, actual, over/short) → voided → end.
    fn build_till(
        &mut self,
        r: &TillReportView,
        _store: &str,
        currency: &str,
        lab: &TillReportLabels,
        orders: &[crate::orders::OrderSummaryView],
    ) {
        let m = |minor: i64| money(minor, currency);

        // ── header ── concise: no branch name or logo, unlike the receipt.
        self.center(&lab.title, RS_TOTAL, Weight::BOLD);
        self.center(
            &format!(
                "{}: {}",
                lab.business_date,
                crate::timefmt::date_in(lab.tz, &r.opened_at)
            ),
            RS_SMALL,
            Weight::NORMAL,
        );
        match (r.is_open, &r.closed_at) {
            (false, Some(c)) => self.center(
                &format!("{}: {}", lab.closed, fmt_dt_z(lab, c)),
                RS_SMALL,
                Weight::NORMAL,
            ),
            _ => self.center(
                &format!("{}: {}", lab.printed_at, fmt_dt_z(lab, &r.printed_at)),
                RS_SMALL,
                Weight::NORMAL,
            ),
        }
        self.rule();

        // ── till info ──
        let t = |k: &str| crate::i18n::tr(&lab.locale, k);
        self.row(&lab.teller, &r.teller_name, RS_BODY, Weight::NORMAL);
        if let Some(code) = r.device_code.as_deref().filter(|c| !c.is_empty()) {
            let range = match (r.order_number_first, r.order_number_last) {
                (Some(a), Some(b)) => format!("{code}  #{code}-{a} … #{code}-{b}"),
                _ => code.to_string(),
            };
            self.row(&t("till.z_device"), &range, RS_SMALL, Weight::NORMAL);
        }
        if r.opened_while_another_open {
            self.center(&format!("! {}", t("till.flagged_badge")), RS_SMALL, Weight::SEMIBOLD);
        }
        if r.verification == "unverified" {
            self.center(&t("till.unverified_badge"), RS_SMALL, Weight::NORMAL);
        }
        self.row(
            &lab.opened,
            &fmt_dt_z(lab, &r.opened_at),
            RS_SMALL,
            Weight::NORMAL,
        );
        if r.is_open {
            self.center(&format!("— {} —", lab.interim), RS_SMALL, Weight::NORMAL);
        } else if let Some(c) = &r.closed_at {
            self.row(&lab.closed, &fmt_dt_z(lab, c), RS_SMALL, Weight::NORMAL);
        }
        self.rule();

        // ── payments ──
        self.center(&lab.payments.to_uppercase(), RS_SMALL, Weight::SEMIBOLD);
        let mut total_orders = 0i64;
        for pl in &r.payment_lines {
            total_orders += pl.order_count;
            self.row(&pl.method, &m(pl.total_minor), RS_BODY, Weight::BOLD);
            self.indented(&format!("{} {}", pl.order_count, lab.orders), RS_SMALL, 16);
        }
        self.row(
            &lab.total_collected,
            &m(r.total_payments_minor),
            RS_BODY,
            Weight::BOLD,
        );
        self.row(
            &lab.transactions,
            &total_orders.to_string(),
            RS_SMALL,
            Weight::NORMAL,
        );
        self.rule();

        // ── drawer operations ──
        self.center(&lab.drawer_ops.to_uppercase(), RS_SMALL, Weight::SEMIBOLD);
        self.row(&lab.cash_in, &m(r.cash_in_minor), RS_BODY, Weight::NORMAL);
        self.row(
            &lab.cash_out,
            &m(-r.cash_out_minor),
            RS_BODY,
            Weight::NORMAL,
        );
        for mv in &r.cash_movements {
            let label = if mv.note.trim().is_empty() {
                &mv.moved_by_name
            } else {
                &mv.note
            };
            self.indented(label, RS_SMALL, 0);
            let sign = if mv.amount_minor < 0 { "−" } else { "+" };
            self.row(
                &format!(
                    "  {}",
                    crate::timefmt::format_in(
                        lab.tz,
                        &mv.created_at,
                        crate::timefmt::TimeStyle::Time,
                        &lab.locale
                    )
                ),
                &format!("{}{}", sign, m(mv.amount_minor.abs())),
                RS_SMALL,
                Weight::NORMAL,
            );
        }
        self.rule();

        // ── cash spot reports viewed (who, when, printed, whose PIN) ──
        if !r.spot_views.is_empty() {
            let tr = |k: &str| crate::i18n::tr(&lab.locale, k);
            self.center(&tr("spot.views").to_uppercase(), RS_SMALL, Weight::SEMIBOLD);
            for v in &r.spot_views {
                let when = crate::timefmt::format_in(lab.tz, &v.viewed_at, crate::timefmt::TimeStyle::Time, &lab.locale);
                let mut who = v.viewed_by_name.clone();
                if let Some(a) = &v.approved_by_name {
                    who = format!("{who} · {} {a}", tr("spot.approved_by"));
                }
                if v.printed {
                    who = format!("{who} · {}", tr("spot.printed"));
                }
                self.indented(&format!("{when}  {who}"), RS_SMALL, 0);
            }
            self.rule();
        }

        // ── cash reconciliation ──
        self.center(&lab.cash_recon.to_uppercase(), RS_SMALL, Weight::SEMIBOLD);
        self.row(
            &lab.opening,
            &m(r.opening_cash_minor),
            RS_BODY,
            Weight::NORMAL,
        );
        // Opening mismatch: the teller counted a different opening float than the
        // suggested (last close) — show the signed difference + the reason.
        if r.opening_cash_was_edited {
            if let Some(orig) = r.opening_cash_original_minor {
                let diff = r.opening_cash_minor - orig;
                let sign = if diff < 0 { "−" } else { "+" };
                self.row(
                    &lab.opening_mismatch,
                    &format!("{}{}", sign, m(diff.abs())),
                    RS_SMALL,
                    Weight::NORMAL,
                );
            }
            if let Some(reason) = r
                .opening_cash_edit_reason
                .as_deref()
                .filter(|s| !s.trim().is_empty())
            {
                self.indented(&format!("{}: {}", lab.opening_reason, reason), RS_SMALL, 16);
            }
        }
        self.row(
            &lab.expected,
            &m(r.expected_cash_minor),
            RS_BODY,
            Weight::NORMAL,
        );
        match r.closing_cash_declared_minor {
            Some(declared) => {
                self.row(&lab.actual, &m(declared), RS_BODY, Weight::BOLD);
                // Difference = expected (system) − counted. Positive = short, negative = over.
                let diff = r.expected_cash_minor - declared;
                let (label, amount) = if diff == 0 {
                    (&lab.difference, 0)
                } else if diff > 0 {
                    (&lab.short_by, diff)
                } else {
                    (&lab.over_by, -diff)
                };
                self.row(label, &m(amount), RS_BODY, Weight::BOLD);
            }
            None => self.center(&format!("({})", lab.not_closed), RS_SMALL, Weight::NORMAL),
        }
        // ── payment check (per-method close reconciliation) ──
        if !r.reconciliation.is_empty() {
            self.rule();
            self.center(&t("till.z_reconciliation").to_uppercase(), RS_SMALL, Weight::SEMIBOLD);
            for l in &r.reconciliation {
                let label = if l.label.is_empty() { &l.method } else { &l.label };
                self.row(label, &m(l.system_total_minor), RS_BODY, Weight::NORMAL);
                match l.status.as_str() {
                    "checked" => self.indented(&format!("✓ {}", t("till.reconcile_checked")), RS_SMALL, 16),
                    "disagreed" => {
                        let declared = l.declared_amount_minor.map(|v| m(v)).unwrap_or_default();
                        self.indented(&format!("✗ {} {}", t("till.reconcile_disagree"), declared), RS_SMALL, 16);
                        if let Some(n) = l.note.as_deref().filter(|n| !n.trim().is_empty()) {
                            self.indented(n, RS_SMALL, 32);
                        }
                    }
                    _ => self.indented(&t("till.reconcile_unreviewed"), RS_SMALL, 16),
                }
            }
        }
        if let Some(old) = r.old_bills_count {
            self.rule();
            self.row(&t("till.z_old_bills"), &old.to_string(), RS_BODY, Weight::NORMAL);
        }
        if let Some(n) = r.held_orders_left_open.filter(|n| *n > 0) {
            self.rule();
            let total = r.held_orders_left_open_total_minor.map(|v| format!(" · {}", m(v))).unwrap_or_default();
            self.row(&t("till.z_held_left_open"), &format!("{n}{total}"), RS_BODY, Weight::NORMAL);
        }
        if r.voided_amount_minor > 0 {
            self.rule();
            self.row(
                &lab.voided,
                &m(r.voided_amount_minor),
                RS_BODY,
                Weight::NORMAL,
            );
        }

        // ── orders (only when the teller expanded + printed) ──
        if !orders.is_empty() {
            self.rule();
            self.center(&lab.orders.to_uppercase(), RS_SMALL, Weight::SEMIBOLD);
            for o in orders {
                let num = match o.order_number {
                    _ if !o.display_number.is_empty() => format!("#{}", o.display_number),
                    Some(n) => format!("#{n}"),
                    None => "—".to_string(),
                };
                let left = format!(
                    "{}  {}",
                    num,
                    crate::timefmt::format_in(
                        lab.tz,
                        &o.created_at,
                        crate::timefmt::TimeStyle::Time,
                        &lab.locale
                    )
                );
                self.row(&left, &m(o.total_minor), RS_SMALL, Weight::NORMAL);
                // Payment method under the row — the on-screen preview shows
                // it, so the printed report must too (parity).
                if !o.payment_label.is_empty() {
                    self.indented(&o.payment_label, RS_SMALL, 16);
                }
                // Voided orders were never collected — flag them under the row.
                if o.status == "voided" {
                    self.indented(&lab.voided, RS_SMALL, 16);
                }
            }
        }

        self.rule();
        self.center(
            &format!("— {} —", lab.end_of_report),
            RS_SMALL,
            Weight::SEMIBOLD,
        );
        self.gap(self.bottom_pad);
    }

    /// Walk a kitchen slip top-to-bottom: heading, table, the notes that
    /// apply to the whole slip ONCE, then every item with only its own
    /// note. No logo, no money, no footer beyond the ticket/time/teller.
    fn build_kitchen_slip(&mut self, slip: &KitchenSlip, labels: &KitchenChitLabels) {
        self.center(&labels.heading, RS_BODY, Weight::BOLD);
        if let Some(t) = slip.table_label.as_deref().filter(|s| !s.trim().is_empty()) {
            self.center(&format!("{} {}", labels.table, t.trim()), RS_TOTAL, Weight::BOLD);
        }
        self.rule();

        let notes: Vec<&String> = slip.top_notes.iter().filter(|n| !n.trim().is_empty()).collect();
        for n in &notes {
            self.indented(&format!("{} {}", labels.note, n.trim()), RS_BODY, 0);
        }
        if !notes.is_empty() {
            self.rule();
        }

        for (i, it) in slip.items.iter().enumerate() {
            if i > 0 {
                self.gap(self.sx(8));
            }
            let name = name_with_size(&it.item, &it.size_label);
            self.row(&format!("{}× {}", it.qty.max(1), name), "", RS_TOTAL, Weight::BOLD);
            if let Some(c) = it.combo.as_deref().filter(|s| !s.trim().is_empty()) {
                self.indented_w(&format!("» {}", c.trim()), RS_SMALL, Weight::BOLD, 16);
            }
            for m in it.modifiers.iter().filter(|m| !m.trim().is_empty()) {
                self.indented(&format!("- {}", m.trim()), RS_SMALL, 16);
            }
            if let Some(n) = it.note.as_deref().filter(|s| !s.trim().is_empty()) {
                self.indented(&format!("{} {}", labels.note, n.trim()), RS_SMALL, 0);
            }
            // The recipe card: what goes into one, then the steps in order.
            if !it.recipe.is_empty() {
                self.gap(self.sx(4));
                self.indented_w(&labels.recipe, RS_BODY, Weight::BOLD, 0);
                for r in &it.recipe {
                    self.indented(&format!("• {}", r.trim()), RS_SMALL, 16);
                }
            }
            if !it.steps.is_empty() {
                self.gap(self.sx(4));
                self.indented_w(&labels.steps, RS_BODY, Weight::BOLD, 0);
                for (n, st) in it.steps.iter().enumerate() {
                    self.indented(&format!("{}. {}", n + 1, st.trim()), RS_SMALL, 16);
                }
            }
        }

        self.rule();
        let foot = match slip.ticket_ref.as_deref().filter(|s| !s.trim().is_empty()) {
            Some(r) => format!("{}  {}", r.trim(), slip.at),
            None => slip.at.clone(),
        };
        self.center(&foot, RS_SMALL, Weight::NORMAL);
        if let Some(by) = slip.teller.as_deref().filter(|s| !s.trim().is_empty()) {
            self.center(by.trim(), RS_SMALL, Weight::NORMAL);
        }
        self.gap(self.bottom_pad);
    }

    /// One item line: the base price for ONE unit, each paid modifier with
    /// what it adds to one unit ("+ Extra shot ×3  +30.00"), then
    /// "2 × 95.00  190.00" — so the rows add up on paper. A plain line (no paid
    /// modifiers) stays one row. When the per-unit split can't be derived
    /// exactly (a reward or a rounding line), the line prints its total only.
    fn item(&mut self, line: &ReceiptLineView, cur: &str) {
        let name = name_with_size(&line.name, &line.size_label);
        let qty = line.qty.max(1);
        let mods: Vec<&ReceiptModifierView> =
            line.addons.iter().chain(line.optionals.iter()).collect();
        let paid: i64 = mods.iter().map(|m| m.price_minor.max(0)).sum();
        let per_unit = (line.line_total_minor % qty == 0).then(|| line.line_total_minor / qty);
        let base = per_unit.map(|u| u - paid).filter(|b| *b >= 0 && paid > 0);

        match base {
            Some(base) => self.row(&name, &money(base, cur), RS_BODY, Weight::BOLD),
            None if qty > 1 => self.row(
                &format!("{}× {}", qty, name),
                &money(line.line_total_minor, cur),
                RS_BODY,
                Weight::BOLD,
            ),
            None => self.row(&name, &money(line.line_total_minor, cur), RS_BODY, Weight::BOLD),
        }
        let priced = base.is_some();
        if let Some(reward) = &line.reward_label {
            self.indented_w(&format!("★ {reward}"), RS_SMALL, Weight::BOLD, 16);
        }
        // A staff drink: normal price above, the pool's comp as a line
        // discount here (already off the subtotal).
        if let Some(staff) = &line.staff_label {
            self.row(
                &format!("  ★ {staff}"),
                &format!("-{}", money(line.staff_comp_minor, cur)),
                RS_SMALL,
                Weight::BOLD,
            );
        }
        for mo in line.addons.iter().chain(line.optionals.iter()) {
            self.modifier(mo, cur, 16, priced);
        }
        if let Some(unit) = per_unit.filter(|_| priced) {
            self.gap(self.sx(2));
            self.row(
                &format!("{} × {}", qty, money(unit, cur)),
                &money(line.line_total_minor, cur),
                RS_BODY,
                Weight::BOLD,
            );
        }
        self.gap(self.sx(6));
    }

    /// A combo (C12): its name with `n × P`, then each of its items indented —
    /// name and size, `+surcharge` when it cost more — and the item's add-ons
    /// indented once more with their prices. Whole-line figures throughout.
    fn combo_item(&mut self, line: &ReceiptLineView, cur: &str) {
        let qty = line.qty.max(1);
        let head = if qty > 1 { format!("{}× {}", qty, line.name) } else { line.name.clone() };
        self.row(&head, &money(line.unit_price_minor * qty, cur), RS_BODY, Weight::BOLD);
        for p in &line.parts {
            let name = name_with_size(&p.name, &p.size_label);
            let left = if p.qty > 1 { format!("{}× {}", p.qty, name) } else { name };
            if p.surcharge_minor > 0 {
                self.row(
                    &format!("   {left}"),
                    &format!("+{}", money(p.surcharge_minor, cur)),
                    RS_SMALL,
                    Weight::BOLD,
                );
            } else {
                self.indented_w(&left, RS_SMALL, Weight::BOLD, 16);
            }
            for mo in p.addons.iter().chain(p.optionals.iter()) {
                self.modifier(mo, cur, 32, true);
            }
        }
        self.gap(self.sx(6));
    }

    /// A modifier under its line. A paid one shows what it adds (its amount
    /// already × its count) when `priced`; a free one is a plain instruction.
    fn modifier(&mut self, m: &ReceiptModifierView, cur: &str, indent: i32, priced: bool) {
        if m.price_minor > 0 && priced {
            let indent = self.sx(indent);
            let right = self.shape(
                &format!("+{}", money(m.price_minor, cur)),
                RS_SMALL,
                Weight::BOLD,
                self.content_w(),
            );
            let (rw, rh) = Self::measure(&right);
            let buf = self.shape(
                &format!("+ {}", m.name),
                RS_SMALL,
                Weight::BOLD,
                self.content_w() - indent - rw.ceil() as i32 - self.sx(12),
            );
            let (_, lh) = Self::measure(&buf);
            let oy = self.y;
            self.blit(&buf, self.margin + indent, oy);
            let rx = self.width - self.margin - rw.round() as i32 - Self::rtl_lead(&right);
            self.blit(&right, rx, oy);
            self.y += lh.max(rh).ceil() as i32;
        } else {
            self.indented(&format!("+ {}", m.name), RS_SMALL, indent);
        }
    }
}

/// The catalog's sentinel for an item with no real size choice — noise on a
/// receipt, not a size the customer picked.
fn is_one_size(s: &str) -> bool {
    let s = s.trim();
    s.eq_ignore_ascii_case("one_size") || s.eq_ignore_ascii_case("one size")
}

fn name_with_size(base: &str, size: &Option<String>) -> String {
    match size {
        Some(s) if !s.is_empty() && !is_one_size(s) => format!("{} ({})", base, s),
        _ => base.to_string(),
    }
}

fn fmt_dt(lab: &crate::receipt::ReceiptLabels, rfc3339: &str) -> String {
    crate::timefmt::format_in(
        lab.tz,
        rfc3339,
        crate::timefmt::TimeStyle::Receipt,
        &lab.locale,
    )
}

fn fmt_dt_z(lab: &TillReportLabels, rfc3339: &str) -> String {
    crate::timefmt::format_in(
        lab.tz,
        rfc3339,
        crate::timefmt::TimeStyle::Receipt,
        &lab.locale,
    )
}

// ── logo decode + threshold ──────────────────────────────────────────────────

/// Crop transparent / near-white borders so a logo padded with empty canvas
/// sizes by its visible mark. A fully blank image is returned unchanged.
fn trim_blank(img: image::RgbaImage) -> image::RgbaImage {
    let (w, h) = img.dimensions();
    let ink = |x: u32, y: u32| {
        let [r, g, b, a] = img.get_pixel(x, y).0;
        a > 24 && (r as u16 + g as u16 + b as u16) < 3 * 235
    };
    let (mut x0, mut y0, mut x1, mut y1) = (w, h, 0u32, 0u32);
    for y in 0..h {
        for x in 0..w {
            if ink(x, y) {
                x0 = x0.min(x);
                y0 = y0.min(y);
                x1 = x1.max(x);
                y1 = y1.max(y);
            }
        }
    }
    if x0 > x1 || y0 > y1 {
        return img;
    }
    image::imageops::crop_imm(&img, x0, y0, x1 - x0 + 1, y1 - y0 + 1).to_image()
}

/// Decode (PNG/JPEG), composite over white, scale to fit `max_w`×`max_h`
/// preserving aspect, then threshold to 1-bit — any pixel with visible ink
/// prints solid black rather than a dithered halftone, since a logo on
/// thermal paper reads as a clean mark, not a gray dot pattern. Returns
/// `(width, height, ink)` where `ink[y*w+x]` is `255` (black) or `0` (white).
/// `None` if the bytes aren't a decodable image.
fn decode_logo(bytes: &[u8], max_w: u32, max_h: u32) -> Option<(usize, usize, Vec<u8>)> {
    let img = image::load_from_memory(bytes).ok()?;
    let rgba = trim_blank(img.to_rgba8());
    let (w0, h0) = (rgba.width().max(1), rgba.height().max(1));
    // Fit the box; a small upload may grow up to 4× so it isn't a speck, but
    // never past the box.
    let scale = (max_w as f32 / w0 as f32)
        .min(max_h as f32 / h0 as f32)
        .min(4.0);
    let tw = ((w0 as f32 * scale).round() as u32).max(1);
    let th = ((h0 as f32 * scale).round() as u32).max(1);
    let scaled = image::imageops::resize(&rgba, tw, th, image::imageops::FilterType::Lanczos3);

    let (w, h) = (scaled.width() as usize, scaled.height() as usize);
    // Any pixel with meaningfully more ink than paper prints solid black —
    // no gray survives as a halftone dot.
    let mut out = vec![0u8; w * h];
    for (i, p) in scaled.pixels().enumerate() {
        let [r, gc, b, a] = p.0;
        let af = a as f32 / 255.0;
        let over = |c: u8| c as f32 * af + 255.0 * (1.0 - af);
        let lum = 0.299 * over(r) + 0.587 * over(gc) + 0.114 * over(b);
        out[i] = if 1.0 - lum / 255.0 >= 0.35 { 255 } else { 0 };
    }
    Some((w, h, out))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::checkout::ReceiptView;
    use crate::receipt::ReceiptLabels;

    fn ctx() -> EscPosCtx {
        EscPosCtx {
            store_name: "Cafe Madar".into(),
            currency: "EGP".into(),
            width: 48,
            labels: ReceiptLabels {
                order: "Order".into(),
                reference: "Ref".into(),
                voided: "VOIDED".into(),
                delivery: "Delivery".into(),
                channel_in_mall: "In-Mall".into(),
                channel_outside: "Outside".into(),
                customer: "Customer".into(),
                phone: "Phone".into(),
                address: "Addr".into(),
                zone: "Zone".into(),
                delivery_ref: "Delivery Ref".into(),
                payment_hint: "Payment".into(),
                notes: "Notes".into(),
                subtotal: "Subtotal".into(),
                discount: "Discount".into(),
                service_charge: "Service".into(),
                tax: "Tax".into(),
                vat_included: "VAT (included)".into(),
                prices_include_vat: "Prices include VAT".into(),
                service_waived: "Service charge removed".into(),
                delivery_fee: "Delivery".into(),
                total: "Total".into(),
                tip: "Tip".into(),
                cash: "Cash".into(),
                change: "Change".into(),
                payment: "Payment".into(),
                teller: "Teller".into(),
                served_by: "Served by".into(),
                queued: "Saved — will sync".into(),
                thank_you: "Thank you!".into(),
                locale: "en".into(),
                tz: chrono_tz::UTC,
            },
        }
    }

    fn receipt() -> ReceiptView {
        ReceiptView {
            local_order_id: "abcdef12-0000-0000-0000-000000000000".into(),
            order_number: Some(42),
            display_number: String::new(),
            order_ref: None,
            is_voided: false,
            lines: vec![ReceiptLineView {
                name: "شاورما".into(), // Arabic — exercises shaping + bidi
                qty: 2,
                size_label: Some("Large".into()),
                line_total_minor: 12000,
                reward_label: None,
                staff_label: None,
                staff_comp_minor: 0,
                addons: vec![ReceiptModifierView {
                    name: "Extra cheese".into(),
                    price_minor: 500,
                }],
                optionals: vec![],
                kind: "item".into(),
                unit_price_minor: 5500,
                parts: vec![],
                deal_minor: 0,
            }],
            payment_label: "Cash".into(),
            subtotal_minor: 12500,
            discount_minor: 0,
            tax_minor: 0,
            service_charge_minor: 0,
            tax_inclusive: false,
            tax_rate: 0.0,
            service_charge_waived_minor: 0,
            service_charge_waived_by_name: None,
            delivery_fee_minor: 0,
            total_minor: 12500,
            tip_minor: 0,
            amount_tendered_minor: 15000,
            change_minor: 2500,
            is_cash: true,
            customer_name: None,
            teller_name: Some("Mona".into()),
            is_delivery: false,
            delivery_channel: None,
            customer_phone: None,
            delivery_address: None,
            delivery_zone: None,
            delivery_ref: None,
            payment_hint: None,
            delivery_notes: None,
            queued_offline: false,
            created_at: "2026-06-24T18:30:00+03:00".into(),
            loyalty_notice: None,
            staff_notice: None,
            deals: vec![],
            payments: vec![],
        }
    }

    #[test]
    fn renders_full_width_nonblank_bitmap() {
        let bmp = render_receipt(&receipt(), &ctx(), None, PRINT_WIDTH);
        assert_eq!(bmp.width, PRINT_WIDTH);
        assert!(
            bmp.rows > 200,
            "receipt should be a few hundred dots tall, got {}",
            bmp.rows
        );
        assert_eq!(bmp.bytes.len(), bmp.row_bytes() * bmp.rows as usize);
        // Not blank: shaping actually put ink down.
        assert!(
            bmp.bytes.iter().any(|&b| b != 0),
            "bitmap is entirely blank"
        );
    }

    #[test]
    fn renders_narrow_58mm_roll_to_384_dots() {
        // A 58 mm portable (384 dots) must render to exactly that width, stay
        // non-blank, and — being a scaled miniature — come out shorter than the
        // 72 mm render of the same receipt.
        let narrow = render_receipt(&receipt(), &ctx(), None, 384);
        let wide = render_receipt(&receipt(), &ctx(), None, PRINT_WIDTH);
        assert_eq!(narrow.width, 384);
        assert_eq!(narrow.row_bytes(), 48); // 384 / 8
        assert_eq!(
            narrow.bytes.len(),
            narrow.row_bytes() * narrow.rows as usize
        );
        assert!(
            narrow.bytes.iter().any(|&b| b != 0),
            "narrow bitmap is entirely blank"
        );
        assert!(
            narrow.rows < wide.rows,
            "58 mm miniature ({} rows) should be shorter than 72 mm ({} rows)",
            narrow.rows,
            wide.rows
        );
    }

    /// A split prints each leg's amount instead of a Cash 0.00 / Change 0.00
    /// pair: the paper used to show nothing paid on a split sale.
    #[test]
    fn a_split_prints_its_legs_not_a_zero_cash_tender() {
        use crate::checkout::ReceiptPaymentView;
        let leg = |label: &str, amount_minor| ReceiptPaymentView { label: label.into(), amount_minor };
        let printed = |r: &ReceiptView| {
            let mut p = Renderer::new(PRINT_WIDTH);
            p.build(r, &ctx(), None);
            p.shaped
        };
        let money_of = |v: i64| money(v, &ctx().currency);
        // Booked against cash (the largest leg), no tender, as the till sends it.
        let mut two = receipt();
        two.amount_tendered_minor = 0;
        two.change_minor = 0;
        two.payments = vec![leg("Cash", 7500), leg("Card", 5000)];
        let text = printed(&two);
        for (label, amount) in [("Cash", 7500), ("Card", 5000)] {
            let at = text.iter().position(|t| t == label).unwrap_or_else(|| panic!("{label} leg: {text:?}"));
            // A row shapes its amount, then its label.
            assert_eq!(text[at - 1], money_of(amount), "{label} amount: {text:?}");
        }
        assert!(!text.iter().any(|t| *t == ctx().labels.change), "no Change row: {text:?}");
        assert_eq!(text.iter().filter(|t| *t == "Cash").count(), 1, "one Cash row, the leg's: {text:?}");

        let mut three = two.clone();
        three.payments = vec![leg("Cash", 5000), leg("Card", 5000), leg("Wallet", 2500)];
        let text = printed(&three);
        assert!(text.iter().any(|t| t == "Wallet") && text.iter().any(|t| *t == money_of(2500)));

        // A single cash payment still prints its tender and change.
        let text = printed(&receipt());
        assert!(text.iter().any(|t| *t == money_of(15000)) && text.iter().any(|t| *t == money_of(2500)));
    }

    /// The printed receipt carries the service charge line (it used to be
    /// missing, so a table's printed lines did not add up), the inclusive note
    /// and a waiver: each is a row of its own on the paper.
    #[test]
    fn prints_the_service_charge_the_inclusive_note_and_a_waiver() {
        let base = receipt();
        let rows = |r: &ReceiptView| render_receipt(r, &ctx(), None, PRINT_WIDTH).rows;
        let mut with_service = base.clone();
        with_service.service_charge_minor = 180;
        assert!(rows(&with_service) > rows(&base), "a service charge adds a line");
        let mut inclusive = with_service.clone();
        inclusive.tax_inclusive = true;
        assert!(rows(&inclusive) > rows(&with_service), "\"Prices include VAT\" adds a line");
        let mut waived = base.clone();
        waived.service_charge_waived_minor = 180;
        waived.service_charge_waived_by_name = Some("Mona".into());
        assert!(rows(&waived) > rows(&base), "a waiver is stated");
    }

    #[test]
    fn render_is_deterministic() {
        let (a, b) = (
            render_receipt(&receipt(), &ctx(), None, PRINT_WIDTH),
            render_receipt(&receipt(), &ctx(), None, PRINT_WIDTH),
        );
        assert_eq!(a, b, "same input must produce a byte-identical bitmap");
    }

    #[test]
    fn ignores_undecodable_logo() {
        // A bogus "logo" must not panic or abort the render — just no logo.
        let bmp = render_receipt(&receipt(), &ctx(), Some(b"not an image"), PRINT_WIDTH);
        assert!(bmp.rows > 200);
    }

    fn till_labels() -> TillReportLabels {
        TillReportLabels {
            title: "Till Close Report".into(),
            business_date: "Business Date".into(),
            printed_at: "Printed at".into(),
            teller: "Teller".into(),
            opened: "Opened".into(),
            closed: "Closed".into(),
            interim: "Interim Report (Till Still Open)".into(),
            payments: "Payments".into(),
            orders: "orders".into(),
            total_collected: "Total Collected".into(),
            drawer_ops: "Drawer Operations".into(),
            cash_in: "Cash in".into(),
            cash_out: "Cash out".into(),
            cash_recon: "Cash Reconciliation".into(),
            opening: "Opening cash".into(),
            opening_mismatch: "Opening mismatch".into(),
            opening_reason: "Reason".into(),
            expected: "Expected in Drawer".into(),
            actual: "Actual in Drawer".into(),
            not_closed: "Till not yet closed".into(),
            difference: "Difference".into(),
            short_by: "Short by".into(),
            over_by: "Over by".into(),
            voided: "Voided".into(),
            refunds: "Refunds".into(),
            refunds_cash: "Refunds in cash".into(),
            cash_in_refunded: "Cash on refunded sales".into(),
            total_tax: "Tax (net of refunds)".into(),
            total_service: "Service charge (net of refunds)".into(),
            service_waived: "Service charge waived".into(),
            transactions: "Transactions".into(),
            end_of_report: "End of Report".into(),
            cash_moves: "Cash moves".into(),
            by_method: "By method".into(),
            locale: "en".into(),
            tz: chrono_tz::UTC,
        }
    }

    fn till_report() -> TillReportView {
        TillReportView {
            teller_name: "Mona".into(),
            opened_at: "2026-06-24T09:00:00+03:00".into(),
            closed_at: Some("2026-06-24T21:30:00+03:00".into()),
            printed_at: "2026-06-24T21:31:00+03:00".into(),
            is_open: false,
            closing_cash_declared_minor: Some(27500),
            opening_cash_was_edited: true,
            opening_cash_original_minor: Some(8000),
            opening_cash_edit_reason: Some("Float top-up".into()),
            expected_cash_minor: 28000,
            opening_cash_minor: 10000,
            total_payments_minor: 20000,
            net_payments_minor: 20000,
            voided_amount_minor: 750,
            refunds_issued_minor: 0,
            refunds_issued_cash_minor: 0,
            refunds_issued_count: 0,
            cash_in_refunded_sales_minor: 0,
            total_tax_minor: 0,
            total_service_charge_minor: 0,
            service_charge_waived_count: 0,
            service_charge_waived_minor: 0,
            cash_movements_net_minor: -2000,
            cash_in_minor: 0,
            cash_out_minor: 2000,
            payment_lines: vec![
                crate::till::TillReportPaymentLine {
                    method: "Cash".into(),
                    is_cash: true,
                    order_count: 5,
                    total_minor: 12000,
                },
                crate::till::TillReportPaymentLine {
                    method: "Card".into(),
                    is_cash: false,
                    order_count: 3,
                    total_minor: 8000,
                },
            ],
            cash_movements: vec![crate::till::TillReportCashLine {
                amount_minor: -2000,
                note: "مصروف".into(), // Arabic note — exercises shaping in the report too
                moved_by_name: "Mona".into(),
                created_at: "2026-06-24T19:00:00+03:00".into(),
            }],
            from_server: true,
            device_code: None,
            order_number_first: None,
            order_number_last: None,
            reconciliation: vec![],
            old_bills_count: None,
            open_bills_count: None,
            held_orders_left_open: None,
            held_orders_left_open_total_minor: None,
            opened_while_another_open: false,
            verification: "server".into(),
            spot_views: Vec::new(),
        }
    }

    #[test]
    fn z_report_renders_reconciliation_and_old_bills() {
        let mut report = till_report();
        report.device_code = Some("36B".into());
        report.order_number_first = Some(1);
        report.order_number_last = Some(42);
        report.old_bills_count = Some(3);
        report.held_orders_left_open = Some(2);
        report.held_orders_left_open_total_minor = Some(12_500);
        report.opened_while_another_open = true;
        report.reconciliation = vec![
            crate::till::ReconciliationLineView {
                method: "Card".into(),
                label: "CIB – counter".into(),
                is_cash: false,
                system_total_minor: 8000,
                status: "disagreed".into(),
                declared_amount_minor: Some(7500),
                note: Some("machine batch cut early".into()),
                changed_after_close: false,
            },
            crate::till::ReconciliationLineView {
                method: "Wallet".into(),
                label: "Wallet".into(),
                is_cash: false,
                system_total_minor: 500,
                status: "checked".into(),
                declared_amount_minor: None,
                note: None,
                changed_after_close: false,
            },
        ];
        let mut r = Renderer::new(PRINT_WIDTH);
        r.build_till(&report, "Store", "EGP", &till_labels(), &[]);
        let text = r.shaped.join("\n");
        for want in [
            "Payment check".to_uppercase().as_str(),
            "CIB – counter",
            "machine batch cut early",
            "Checked",
            "Old open bills",
            "#36B-1",
            "#36B-42",
            "Opened while another till was open",
        ] {
            assert!(text.contains(want), "missing {want:?} in:\n{text}");
        }
    }

    #[test]
    fn receipt_prints_the_device_display_number() {
        let mut rc = receipt();
        rc.display_number = "36B-12".into();
        let mut r = Renderer::new(PRINT_WIDTH);
        r.build(&rc, &ctx(), None);
        assert!(r.shaped.iter().any(|l| l.contains("#36B-12")));
    }

    #[test]
    fn renders_till_report_bitmap() {
        let bmp = render_till_report(
            &till_report(),
            "Cafe Madar",
            "EGP",
            &till_labels(),
            &[],
            PRINT_WIDTH,
        );
        assert_eq!(bmp.width, PRINT_WIDTH);
        assert!(bmp.rows > 150);
        assert!(
            bmp.bytes.iter().any(|&b| b != 0),
            "till report bitmap is blank"
        );
    }

    fn save_png(bmp: &Bitmap, path: &str) {
        let wb = bmp.row_bytes();
        let mut img = image::GrayImage::new(bmp.width, bmp.rows);
        for y in 0..bmp.rows {
            for x in 0..bmp.width {
                let bit = bmp.bytes[y as usize * wb + (x >> 3) as usize] & (0x80 >> (x & 7));
                img.put_pixel(x, y, image::Luma([if bit != 0 { 0 } else { 255 }]));
            }
        }
        img.save(path).unwrap();
        eprintln!("wrote {} ({}x{})", path, bmp.width, bmp.rows);
    }

    // Visual check: `cargo test -p madar-core dump_receipt_png -- --ignored`
    // writes the rendered receipt + shift report to /tmp to be eyeballed.
    #[test]
    #[ignore]
    fn dump_receipt_png() {
        save_png(
            &render_receipt(&receipt(), &ctx(), None, PRINT_WIDTH),
            "/tmp/receipt.png",
        );
        save_png(
            &render_till_report(
                &till_report(),
                "Cafe Madar",
                "EGP",
                &till_labels(),
                &[],
                PRINT_WIDTH,
            ),
            "/tmp/till_report.png",
        );
        // Synthetic 4:1 wordmark (border + diagonal) to check logo sizing.
        let mut logo = image::RgbaImage::new(800, 200);
        for (x, y, px) in logo.enumerate_pixels_mut() {
            let border = x < 10 || x >= 790 || y < 10 || y >= 190;
            let diag = (x as i64 / 4) - y as i64;
            *px = if border || diag.abs() < 8 {
                image::Rgba([0, 0, 0, 255])
            } else {
                image::Rgba([0, 0, 0, 0])
            };
        }
        let mut png = std::io::Cursor::new(Vec::new());
        image::DynamicImage::ImageRgba8(logo)
            .write_to(&mut png, image::ImageFormat::Png)
            .unwrap();
        save_png(
            &render_receipt(&receipt(), &ctx(), Some(png.get_ref()), PRINT_WIDTH),
            "/tmp/receipt_logo.png",
        );
    }

    // ── one instant, one wall-clock: receipt, Z rows, cash moves, screen ──

    /// 23:30 UTC on Sep 12 is 02:30 on Sep 13 in Cairo (UTC+3, summer time).
    const LATE: &str = "2026-09-12T23:30:00+00:00";

    fn printed_till(tz: chrono_tz::Tz, at: &str) -> Vec<String> {
        let mut report = till_report();
        report.opened_at = at.into();
        report.printed_at = at.into();
        report.closed_at = Some(at.into());
        report.cash_movements[0].created_at = at.into();
        let order = crate::orders::OrderSummaryView {
            id: "o1".into(),
            order_number: Some(7),
            subtotal_minor: 100,
            tax_minor: 0,
            total_minor: 100,
            payment_label: "Cash".into(),
            status: "completed".into(),
            created_at: at.into(),
            queued: false,
            teller_name: None,
            order_type: "dine_in".into(),
            customer_name: None,
            price_flagged: false,
            order_ref: None,
            display_number: String::new(),
        };
        let mut labels = till_labels();
        labels.tz = tz;
        let mut r = Renderer::new(PRINT_WIDTH);
        r.build_till(&report, "Store", "EGP", &labels, &[order]);
        r.shaped
    }

    fn printed_receipt(tz: chrono_tz::Tz, at: &str) -> Vec<String> {
        let mut rc = receipt();
        rc.created_at = at.into();
        let mut c = ctx();
        c.labels.tz = tz;
        let mut r = Renderer::new(PRINT_WIDTH);
        r.build(&rc, &c, None);
        r.shaped
    }

    #[test]
    fn a_late_order_prints_the_next_calendar_day_everywhere() {
        let cairo = chrono_tz::Africa::Cairo;
        let receipt = printed_receipt(cairo, LATE);
        assert!(
            receipt.iter().any(|t| t == "13/09/2026 02:30 AM"),
            "{receipt:?}"
        );
        let z = printed_till(cairo, LATE);
        assert!(z.iter().any(|t| t == "#7  02:30 AM"), "order row: {z:?}");
        assert!(z.iter().any(|t| t == "  02:30 AM"), "cash move: {z:?}");
        assert!(z.iter().any(|t| t.ends_with("13/09/2026")), "date: {z:?}");
        assert!(
            z.iter().any(|t| t == "13/09/2026 02:30 AM"),
            "header: {z:?}"
        );
        // The screen formats through the same helper and cache.
        let store = crate::store::Store::open("").unwrap();
        store
            .kv_put(crate::checkout::KEY_BRANCH_TZ, "Africa/Cairo")
            .unwrap();
        assert_eq!(
            crate::timefmt::format(&store, LATE, crate::timefmt::TimeStyle::Receipt, "en"),
            "13/09/2026 02:30 AM"
        );
        // Nothing prints the raw UTC wall-clock.
        assert!(!z
            .iter()
            .chain(receipt.iter())
            .any(|t| t.contains("11:30 PM")));
    }

    #[test]
    fn prints_follow_dst_transitions_in_the_branch_zone() {
        let ny = chrono_tz::America::New_York;
        // 2026-03-08 06:59 UTC = 01:59 EST; 07:00 UTC = 03:00 EDT (spring forward).
        assert!(printed_receipt(ny, "2026-03-08T06:59:00Z")
            .iter()
            .any(|t| t == "08/03/2026 01:59 AM"));
        assert!(printed_receipt(ny, "2026-03-08T07:00:00Z")
            .iter()
            .any(|t| t == "08/03/2026 03:00 AM"));
        // 2026-11-01 05:30 UTC = 01:30 EDT; 06:30 UTC = 01:30 EST (fall back).
        let z = printed_till(ny, "2026-11-01T06:30:00Z");
        assert!(z.iter().any(|t| t == "#7  01:30 AM"), "{z:?}");
        // Cairo: 2026-04-23 21:59 UTC = 23:59 EET (last Friday of April); the clock then jumps to 01:00 EEST.
        let cairo = chrono_tz::Africa::Cairo;
        assert!(printed_receipt(cairo, "2026-04-23T21:59:00Z")
            .iter()
            .any(|t| t == "23/04/2026 11:59 PM"));
        assert!(printed_receipt(cairo, "2026-04-23T22:00:00Z")
            .iter()
            .any(|t| t == "24/04/2026 01:00 AM"));
    }

    // ── kitchen chit: raster, not raw text (Arabic/RTL must not garble) ───────

    fn kitchen_labels() -> KitchenChitLabels {
        KitchenChitLabels {
            heading: "المطبخ".into(),
            table: "طاولة".into(),
            note: "ملاحظة:".into(),
            recipe: "Recipe:".into(),
            steps: "Steps:".into(),
        }
    }

    fn arabic_slip() -> KitchenSlip {
        KitchenSlip {
            table_label: Some("طاولة ٤".into()),
            ticket_ref: Some("R-9".into()),
            at: "19:42".into(),
            teller: Some("منى".into()),
            top_notes: vec!["عيد ميلاد — الكيك آخراً".into()],
            items: vec![KitchenSlipItem {
                item: "شاورما دجاج".into(), // "chicken shawarma"
                qty: 2,
                size_label: Some("كبير".into()), // "large"
                modifiers: vec!["زيادة جبنة".into()],
                note: Some("بدون بصل".into()), // "no onions"
                combo: None,
                recipe: Vec::new(),
                steps: Vec::new(),
            }],
        }
    }

    /// An Arabic item name + an Arabic note render to a bitmap without
    /// panicking — the raster path shapes and blits real glyphs (Cairo +
    /// cosmic-text bidi), unlike the old raw-UTF-8 text encoder that a
    /// single-byte-codepage thermal head would have garbled.
    #[test]
    fn an_arabic_kitchen_chit_rasters_without_panicking() {
        let bmp = render_kitchen_chit(&arabic_slip(), &kitchen_labels(), PRINT_WIDTH);
        assert!(bmp.rows > 0 && !bmp.bytes.is_empty(), "a real bitmap, not empty");
    }

    /// The kitchen chit's bytes are a RASTER image (the brand's raster
    /// protocol), never raw UTF-8 text — the bug that garbled Arabic.
    #[test]
    fn kitchen_chit_bytes_are_a_raster_not_raw_text() {
        use crate::receipt::{raster_for, PrinterBrand};
        let bmp = render_kitchen_chit(&arabic_slip(), &kitchen_labels(), PRINT_WIDTH);
        let bytes = raster_for(PrinterBrand::Epson, &bmp, true);
        // Raw UTF-8 text would carry the Arabic bytes verbatim; a raster
        // frame never does — it's ESC/POS raster commands + packed bits.
        let text = "شاورما دجاج";
        assert!(
            !bytes.windows(text.as_bytes().len()).any(|w| w == text.as_bytes()),
            "the Arabic item name must not appear as raw text bytes in the printed frame"
        );
        // A real raster payload: bigger than the bare command bytes, and it
        // is NOT valid UTF-8 as a whole (packed 1-bit pixel data isn't text).
        assert!(bytes.len() > 64);
    }

    /// A multi-item kitchen slip is ONE raster job — the raster path never
    /// emits more than one cut command, however many items are on it (the
    /// commands/count-per-cut are Epson's own concern; here we assert the
    /// slip is built as ONE bitmap, not N concatenated ones).
    #[test]
    fn a_multi_item_kitchen_slip_is_one_continuous_raster() {
        let mut slip = arabic_slip();
        slip.items.push(KitchenSlipItem {
            item: "Fries".into(),
            qty: 1,
            size_label: None,
            modifiers: vec![],
            note: None,
            combo: None,
            recipe: Vec::new(),
            steps: Vec::new(),
        });
        let one_bitmap = render_kitchen_chit(&slip, &kitchen_labels(), PRINT_WIDTH);
        let mut first_only = slip.clone();
        first_only.items.truncate(1);
        let smaller = render_kitchen_chit(&first_only, &kitchen_labels(), PRINT_WIDTH);
        assert!(
            one_bitmap.rows > smaller.rows,
            "the second item adds rows to the SAME bitmap, not a second document"
        );
    }

    // ── B9: Arabic centred lines sit on the paper ─────────────────────────────

    /// Both rolls the tills print on: 58 mm (384 dots) and 80 mm (576 dots).
    const ROLLS: [u32; 2] = [384, PRINT_WIDTH];

    /// The receipt labels exactly as the till builds them in Arabic.
    fn ar_ctx() -> EscPosCtx {
        let tr = |k: &str| crate::i18n::tr("ar", k);
        let mut c = ctx();
        c.store_name = "ARKAN".into();
        c.labels.order = tr("receipt.order");
        c.labels.reference = tr("receipt.ref");
        c.labels.subtotal = tr("order.subtotal");
        c.labels.total = tr("order.total");
        c.labels.cash = tr("receipt.cash");
        c.labels.change = tr("order.change");
        c.labels.thank_you = "شكراً لزيارتكم".into();
        c.labels.locale = "ar".into();
        c
    }

    /// T1's AR receipt: the order label, the number, the date and the Ref.
    fn ar_receipt() -> ReceiptView {
        let mut r = receipt();
        r.display_number = "E38-1".into();
        r.order_ref = Some("ARKAN-260926-E38-0001".into());
        r.created_at = "2026-09-26T03:31:00Z".into();
        r.payment_label = "نقدي".into();
        r
    }

    /// T1's AR chit: a counter sale (no table, no ticket ref), so the foot is
    /// the Arabic time alone; the teller's name in Arabic.
    fn ar_chit() -> KitchenSlip {
        let mut s = arabic_slip();
        s.table_label = None;
        s.ticket_ref = None;
        s.at = crate::timefmt::format_in(
            chrono_tz::UTC,
            "2026-09-26T03:31:00Z",
            crate::timefmt::TimeStyle::Time,
            "ar",
        );
        s.teller = Some("مريم عادل".into());
        s
    }

    fn ar_chit_labels() -> KitchenChitLabels {
        let tr = |k: &str| crate::i18n::tr("ar", k);
        KitchenChitLabels {
            heading: tr("kitchen.chit_heading"),
            table: tr("kitchen.chit_table"),
            note: tr("kitchen.chit_note"),
            recipe: tr("kitchen.recipe"),
            steps: tr("kitchen.steps"),
        }
    }

    /// Every centred line put ink down, all of it on the paper, centred; and
    /// nothing else drawn on the page runs off it either.
    fn assert_on_paper(r: &Renderer, want_centred: &[String], what: &str) {
        let w = r.width;
        for want in want_centred {
            assert!(
                r.centered.iter().any(|(t, _)| t == want),
                "{what} @{w}: {want:?} was not drawn centred; centred: {:?}",
                r.centered
            );
        }
        for (text, at) in &r.centered {
            let (_, (x0, y0, x1, y1)) = r.inked[*at].clone();
            assert!(x0 < x1 && y0 < y1, "{what} @{w}: {text:?} put no ink down");
            assert!(
                x0 >= 0 && x1 <= w,
                "{what} @{w}: {text:?} is inked at x {x0}..{x1}, off the {w}-dot paper"
            );
            let mid = (x0 + x1) / 2;
            assert!(
                (mid - w / 2).abs() <= w / 16,
                "{what} @{w}: {text:?} is inked at x {x0}..{x1}, not centred on {}",
                w / 2
            );
        }
        for (text, (x0, _, x1, _)) in &r.inked {
            if x0 < x1 {
                assert!(
                    *x0 >= 0 && *x1 <= w,
                    "{what} @{w}: {text:?} is inked at x {x0}..{x1}, off the {w}-dot paper"
                );
            }
        }
    }

    #[test]
    fn an_arabic_receipt_prints_its_centred_lines_on_the_paper() {
        let (c, rc) = (ar_ctx(), ar_receipt());
        let date = fmt_dt(&c.labels, &rc.created_at);
        assert!(date.contains('ص'), "the AR date is Arabic (RTL): {date:?}");
        let want = [
            c.labels.order.to_uppercase(),
            "#E38-1".to_string(),
            date,
            format!("{} {}", c.labels.reference, "ARKAN-260926-E38-0001"),
            "نقدي".to_string(),
            c.labels.thank_you.clone(),
        ];
        for roll in ROLLS {
            let mut r = Renderer::new(roll);
            r.build(&rc, &c, None);
            assert_on_paper(&r, &want, "AR receipt");
        }
    }

    #[test]
    fn an_arabic_kitchen_chit_prints_its_title_and_time_on_the_paper() {
        let labels = ar_chit_labels();
        let slip = ar_chit();
        assert!(slip.at.contains('ص'), "the AR time is Arabic (RTL): {:?}", slip.at);
        let mut with_table = ar_chit();
        with_table.table_label = Some("٤".into());
        for roll in ROLLS {
            let mut r = Renderer::new(roll);
            r.build_kitchen_slip(&slip, &labels);
            let want = [labels.heading.clone(), slip.at.clone(), "مريم عادل".to_string()];
            assert_on_paper(&r, &want, "AR chit");

            let mut r = Renderer::new(roll);
            r.build_kitchen_slip(&with_table, &labels);
            assert_on_paper(&r, &[format!("{} ٤", labels.table)], "AR chit at a table");
        }
    }

    /// The Z-report's flush-right values (an Arabic date, an Arabic teller
    /// name) and its centred headings land on the paper too.
    #[test]
    fn an_arabic_till_report_prints_on_the_paper() {
        let mut report = till_report();
        report.teller_name = "منى".into();
        let mut labels = till_labels();
        labels.title = "تقرير إغلاق الخزينة".into();
        labels.locale = "ar".into();
        for roll in ROLLS {
            let mut r = Renderer::new(roll);
            r.build_till(&report, "Store", "EGP", &labels, &[]);
            assert_on_paper(&r, &[labels.title.clone()], "AR Z-report");
        }
    }

    /// English is unchanged by the fix: the same checks pass for it.
    #[test]
    fn an_english_receipt_and_chit_stay_centred_on_the_paper() {
        let mut en = receipt();
        en.order_ref = Some("ARKAN-260926-E38-0001".into());
        let want = [
            "ORDER".to_string(),
            "Ref: ARKAN-260926-E38-0001".to_string(),
            "Thank you!".to_string(),
        ];
        let mut c = ctx();
        c.labels.reference = crate::i18n::tr("en", "receipt.ref");
        let chit_labels = KitchenChitLabels {
            heading: "KITCHEN".into(),
            table: "Table".into(),
            note: "Note:".into(),
            recipe: "Recipe:".into(),
            steps: "Steps:".into(),
        };
        let mut slip = arabic_slip();
        slip.at = "03:31 AM".into();
        slip.ticket_ref = None;
        slip.teller = Some("Mariam Adel".into());
        for roll in ROLLS {
            let mut r = Renderer::new(roll);
            r.build(&en, &c, None);
            assert_on_paper(&r, &want, "EN receipt");
            let mut r = Renderer::new(roll);
            r.build_kitchen_slip(&slip, &chit_labels);
            assert_on_paper(&r, &["KITCHEN".to_string(), "03:31 AM".to_string()], "EN chit");
        }
    }

    /// B12: the label already ends in its colon ("Ref:", "مرجع:"), so the
    /// line must not add another ("Ref:: …").
    #[test]
    fn the_ref_line_has_one_colon() {
        for loc in ["en", "ar"] {
            let mut c = ctx();
            c.labels.reference = crate::i18n::tr(loc, "receipt.ref");
            let mut rc = receipt();
            rc.order_ref = Some("ARKAN-1".into());
            let mut r = Renderer::new(PRINT_WIDTH);
            r.build(&rc, &c, None);
            let line = r
                .shaped
                .iter()
                .find(|t| t.contains("ARKAN-1"))
                .unwrap_or_else(|| panic!("{loc}: no Ref line in {:?}", r.shaped));
            assert_eq!(line.matches(':').count(), 1, "{loc}: {line:?}");
            assert_eq!(*line, format!("{} ARKAN-1", c.labels.reference), "{loc}");
        }
    }

    /// Proof renders for the AR print fix: writes the AR/EN receipt, chit
    /// and Z-report at both rolls as PNGs (+ the raw bitmap SHA-256) into
    /// `$MADAR_PRINT_PROOF_DIR`. `cargo test -- --ignored dump_print_proof`.
    #[test]
    #[ignore]
    fn dump_print_proof() {
        use sha2::Digest;
        let Ok(dir) = std::env::var("MADAR_PRINT_PROOF_DIR") else { return };
        std::fs::create_dir_all(&dir).unwrap();
        let mut sums = String::new();
        let mut save = |name: String, bmp: Bitmap| {
            let mut img = image::GrayImage::from_pixel(bmp.width, bmp.rows, image::Luma([255u8]));
            let wb = bmp.row_bytes();
            for y in 0..bmp.rows as usize {
                for x in 0..bmp.width as usize {
                    if bmp.bytes[y * wb + (x >> 3)] & (0x80 >> (x & 7)) != 0 {
                        img.put_pixel(x as u32, y as u32, image::Luma([0u8]));
                    }
                }
            }
            img.save(format!("{dir}/{name}.png")).unwrap();
            let sum: String = sha2::Sha256::digest(&bmp.bytes).iter().map(|b| format!("{b:02x}")).collect();
            sums.push_str(&format!("{sum}  {name}\n"));
        };
        let mut en = receipt();
        en.order_ref = Some("ARKAN-260926-E38-0001".into());
        let mut en_ctx = ctx();
        en_ctx.labels.reference = crate::i18n::tr("en", "receipt.ref");
        let en_chit = {
            let mut s = arabic_slip();
            s.table_label = Some("4".into());
            s.at = "03:31 AM".into();
            s.teller = Some("Mona".into());
            s
        };
        let en_chit_labels = KitchenChitLabels {
            heading: "KITCHEN".into(),
            table: "Table".into(),
            note: "Note:".into(),
            recipe: "Recipe:".into(),
            steps: "Steps:".into(),
        };
        let mut ar_report = till_report();
        ar_report.teller_name = "منى".into();
        let mut ar_till = till_labels();
        ar_till.title = "تقرير إغلاق الخزينة".into();
        ar_till.locale = "ar".into();
        for roll in ROLLS {
            save(format!("ar-receipt-{roll}"), render_receipt(&ar_receipt(), &ar_ctx(), None, roll));
            save(format!("ar-chit-{roll}"), render_kitchen_chit(&ar_chit(), &ar_chit_labels(), roll));
            save(format!("ar-zreport-{roll}"), render_till_report(&ar_report, "Store", "EGP", &ar_till, &[], roll));
            save(format!("en-receipt-noref-{roll}"), render_receipt(&receipt(), &ctx(), None, roll));
            save(format!("en-receipt-ref-{roll}"), render_receipt(&en, &en_ctx, None, roll));
            save(format!("en-chit-{roll}"), render_kitchen_chit(&en_chit, &en_chit_labels, roll));
            save(format!("en-zreport-{roll}"), render_till_report(&till_report(), "Store", "EGP", &till_labels(), &[], roll));
        }
        std::fs::write(format!("{dir}/SHA256SUMS"), sums).unwrap();
    }
}
