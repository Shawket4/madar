//! Spreadsheet export and import for the dashboard (`xlsx_write` / `xlsx_read`
//! on the bridge). Dashboard-only, so it lives in this crate and the POS binary
//! never links it.
//!
//! The export writes the workbook the web dashboard's `src/lib/excel.ts`
//! builds (`exportToExcel` → `buildSheet`). Every decision excel.ts makes —
//! cell values (money ÷ 100, dates as the branch's wall-clock serials, ✓ / —),
//! number formats, the subtitle line, which columns a stat pill spans, the SUM
//! formulas — is made by the host into a laid-out spec (dashboard_core's
//! `WorkbookSpec.toJson()`); this only draws it:
//!
//! ```json
//! { "creator": "Madar", "rtl": false,
//!   "palette": { "brand": "FF14181E", "accent": "FF14181E", "white": "FFFFFFFF",
//!                "zebra": "FFEDF2F3", "text": "FF14181E", "muted": "FF76828B" },
//!   "sheets": [{ "name": "Orders", "title": "Orders", "subtitle": "… · Generated: …",
//!     "columns": [{ "header": "Total", "width": 20, "num_fmt": "#,##0.00 \"EGP\"" }],
//!     "padding_widths": [18, 18, 18, 18, 18],
//!     "stats": [{ "label": "Revenue", "value": 125.5, "from_col": "A", "to_col": "A",
//!                 "num_fmt": "#,##0.00 \"EGP\"" }],
//!     "rows": [[125.5]],
//!     "totals_row": [{ "formula": "SUM(A8:A8)" }],
//!     "header_row": 7, "first_data_row": 8 }] }
//! ```
//!
//! Per sheet: a merged title banner (row 1, 60 pt, right-aligned, the logo at
//! its start), the merged subtitle (row 2), stat pills (rows 4–5), the header
//! (row 7, frozen with everything above it), zebra data rows from row 8 and
//! the totals band; landscape, fit to one page wide. `rtl` (not something the
//! web sets) turns the sheets right-to-left for an Arabic export.
//!
//! A sheet with `"kind": "blocks"` is a sheet of tables (excel.ts
//! `buildBlockSheet`, the recipe book): the same rows 1–6, then the rows the
//! host laid out, each already placed and sized:
//!
//! ```json
//! { "kind": "blocks", "name": "Recipes", "title": "Recipes", "subtitle": "…",
//!   "widths": [34, 9, 15, 15, 18, 18],
//!   "stats": [{ "label": "Items", "value": 2, "from_col": "A", "to_col": "A", "num_fmt": "#,##0" }],
//!   "rows": [
//!     { "kind": "group", "row": 7, "height": 24, "text": "Coffee" },
//!     { "kind": "gap", "row": 8, "height": 6 },
//!     { "kind": "title", "row": 9, "height": 22, "text": "Latte", "note": "   Follows Flat white" },
//!     { "kind": "header", "row": 10, "height": 22, "cells": ["Ingredient", "Unit", "Small"], "num_fmts": [null, null, null] },
//!     { "kind": "body", "row": 11, "height": 20, "cells": ["Beans", "g", 18], "num_fmts": [null, null, null], "zebra": true },
//!     { "kind": "footer", "row": 12, "height": 20, "cells": ["Cost", null, 2.05], "num_fmts": [null, null, "#,##0.00 \"EGP\""], "ruled": true },
//!     { "kind": "caption", "row": 13, "height": 30, "text": "How it's made\n1. Pull a shot" },
//!     { "kind": "gap", "row": 14, "height": 10 }] }
//! ```
//!
//! A band, a title and a caption are merged across every column; a table's
//! first column reads from the start (indented), the rest are centred. A
//! sheet of tables is portrait, one page wide, with nothing frozen. A sheet
//! with no `kind` is a table sheet, as every sheet before it.
//!
//! The import reads every sheet the way the web's `readSheet` reads one
//! (`features/dawam/people.ts`): non-empty rows only, each from column A up
//! to its last value, a date cell as `YYYY-MM-DD`, a formula as its result.

use std::io::Cursor;

use rust_xlsxwriter::{
    Color, DocProperties, Format, FormatAlign, FormatBorder, FormatPattern, Formula, Image,
    ObjectMovement, Workbook, Worksheet, XlsxError,
};
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;

/// The one typeface every cell is set in: the dashboard's own (the web's
/// `EXPORT_FONT`, dashboard_core's `ExcelPalette.font`).
const FONT: &str = "IBM Plex Sans Arabic";
/// A sheet is padded to at least this many columns (the banner's width).
const MIN_COLUMNS: usize = 6;
const DEFAULT_WIDTH: f64 = 20.0;
const PAD_WIDTH: f64 = 18.0;

/// The whole workbook (dashboard_core `WorkbookSpec`).
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct WorkbookSpec {
    pub creator: Option<String>,
    pub palette: Palette,
    /// Right-to-left sheets (an Arabic export).
    pub rtl: bool,
    pub sheets: Vec<AnySheet>,
}

/// One sheet of either kind: a table (no `kind`, or `"table"`) or a sheet of
/// tables (`"kind": "blocks"`).
#[derive(Debug)]
pub enum AnySheet {
    Table(SheetSpec),
    Blocks(BlockSheetSpec),
}

impl<'de> Deserialize<'de> for AnySheet {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        use serde::de::Error;
        let v = Value::deserialize(d)?;
        match v.get("kind").and_then(Value::as_str) {
            None | Some("table") => serde_json::from_value(v)
                .map(AnySheet::Table)
                .map_err(D::Error::custom),
            Some("blocks") => serde_json::from_value(v)
                .map(AnySheet::Blocks)
                .map_err(D::Error::custom),
            Some(other) => Err(D::Error::custom(format!("not a sheet kind: {other:?}"))),
        }
    }
}

impl AnySheet {
    fn name(&self) -> &str {
        match self {
            AnySheet::Table(s) => &s.name,
            AnySheet::Blocks(s) => &s.name,
        }
    }
}

/// The web's `PALETTE`, ARGB hex.
#[derive(Debug, Deserialize)]
#[serde(default)]
pub struct Palette {
    pub brand: String,
    pub accent: String,
    pub white: String,
    pub zebra: String,
    pub text: String,
    pub muted: String,
}

impl Default for Palette {
    fn default() -> Self {
        // Ink on paper: every export token is ink (owner, 2026-11-25).
        Palette {
            brand: "FF14181E".into(),
            accent: "FF14181E".into(),
            white: "FFFFFFFF".into(),
            zebra: "FFEDF2F3".into(),
            text: "FF14181E".into(),
            muted: "FF76828B".into(),
        }
    }
}

/// One sheet, laid out (dashboard_core `SheetSpec`).
#[derive(Debug, Deserialize)]
#[serde(default)]
pub struct SheetSpec {
    pub name: String,
    pub title: String,
    /// The whole second line, already joined.
    pub subtitle: String,
    pub columns: Vec<ColumnSpec>,
    /// Widths of the empty columns that pad the banner to six.
    pub padding_widths: Vec<f64>,
    pub stats: Vec<StatSpec>,
    /// Cell values in column order: a number, a string, or null.
    pub rows: Vec<Vec<Value>>,
    /// The totals band: `{ "formula": "SUM(B8:B9)" }` or a string per column.
    pub totals_row: Option<Vec<Value>>,
    /// 1-based; everything above the first data row stays frozen.
    pub header_row: u32,
    pub first_data_row: u32,
}

impl Default for SheetSpec {
    fn default() -> Self {
        SheetSpec {
            name: String::new(),
            title: String::new(),
            subtitle: String::new(),
            columns: Vec::new(),
            padding_widths: Vec::new(),
            stats: Vec::new(),
            rows: Vec::new(),
            totals_row: None,
            header_row: 7,
            first_data_row: 8,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct ColumnSpec {
    pub header: String,
    pub width: Option<f64>,
    pub num_fmt: Option<String>,
}

/// A sheet of tables, laid out (dashboard_core `BlockSheetSpec`).
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct BlockSheetSpec {
    pub name: String,
    pub title: String,
    /// The whole second line, already joined.
    pub subtitle: String,
    /// Every column's width, already padded to six.
    pub widths: Vec<f64>,
    pub stats: Vec<StatSpec>,
    /// From row 7 on, each placed and sized.
    pub rows: Vec<BlockRowSpec>,
}

/// What a row of a sheet of tables is.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BlockRowKind {
    /// A category's band across the sheet.
    Group,
    /// An empty row of its own height.
    Gap,
    /// A table's title, its note muted after it.
    Title,
    /// The header band.
    Header,
    /// A zebra-striped row of values.
    Body,
    /// A bold summary row (the first ruled off above).
    Footer,
    /// A wrapped line across the sheet.
    Caption,
}

/// One row of a sheet of tables (dashboard_core `BlockRowSpec`).
#[derive(Debug, Deserialize)]
pub struct BlockRowSpec {
    pub kind: BlockRowKind,
    /// 1-based; rows 1–6 are the head's.
    pub row: u32,
    /// Points.
    pub height: f64,
    /// A band's, a title's or a caption's words.
    #[serde(default)]
    pub text: Option<String>,
    /// A title's muted words, spaced as drawn.
    #[serde(default)]
    pub note: Option<String>,
    /// A header's, body's or footer's values: a number, a string or null.
    #[serde(default)]
    pub cells: Vec<Value>,
    /// One per cell; null = General.
    #[serde(default)]
    pub num_fmts: Vec<Option<String>>,
    #[serde(default)]
    pub zebra: bool,
    #[serde(default)]
    pub ruled: bool,
}

/// The first row a sheet of tables lays out (rows 1–6 are every sheet's head).
const FIRST_BLOCK_ROW: u32 = 7;

/// A stat pill over `from_col`..`to_col` (letters) in rows 4–5.
#[derive(Debug, Default, Deserialize)]
#[serde(default)]
pub struct StatSpec {
    pub label: String,
    pub value: Value,
    pub from_col: String,
    pub to_col: String,
    pub num_fmt: Option<String>,
}

/// One sheet read from a file.
#[derive(Debug, PartialEq, Serialize)]
pub struct SheetRows {
    pub name: String,
    pub rows: Vec<Vec<Value>>,
}

/// Why a workbook could not be written or read.
#[derive(Debug, thiserror::Error)]
pub enum XlsxFailure {
    #[error("spec: {0}")]
    Spec(String),
    #[error("xlsx: {0}")]
    Write(String),
    #[error("read: {0}")]
    Read(String),
}

impl From<XlsxError> for XlsxFailure {
    fn from(e: XlsxError) -> Self {
        XlsxFailure::Write(e.to_string())
    }
}

/// `FF14181E` (ARGB) → the RGB colour.
fn color(argb: &str) -> Result<Color, XlsxFailure> {
    let hex = argb.trim().trim_start_matches('#');
    let rgb = if hex.len() == 8 { &hex[2..] } else { hex };
    u32::from_str_radix(rgb, 16)
        .ok()
        .filter(|_| rgb.len() == 6)
        .map(Color::RGB)
        .ok_or_else(|| XlsxFailure::Spec(format!("not a colour: {argb:?}")))
}

struct Colors {
    brand: Color,
    accent: Color,
    white: Color,
    zebra: Color,
    text: Color,
    muted: Color,
}

impl Colors {
    fn of(p: &Palette) -> Result<Self, XlsxFailure> {
        Ok(Colors {
            brand: color(&p.brand)?,
            accent: color(&p.accent)?,
            white: color(&p.white)?,
            zebra: color(&p.zebra)?,
            text: color(&p.text)?,
            muted: color(&p.muted)?,
        })
    }
}

/// `A` → 0, `Z` → 25, `AA` → 26.
fn col_index(letters: &str) -> Option<usize> {
    let letters = letters.trim();
    if letters.is_empty() || !letters.chars().all(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    let n = letters.chars().fold(0usize, |n, c| {
        n * 26 + (c.to_ascii_uppercase() as u8 - b'A') as usize + 1
    });
    Some(n - 1)
}

/// A sheet name Excel accepts (the web's `cleanSheetName`), unique in the book.
fn sheet_name(raw: &str, index: usize, taken: &mut Vec<String>) -> String {
    let clean: String = raw
        .chars()
        .filter(|c| !matches!(c, ':' | '\\' | '/' | '?' | '*' | '[' | ']'))
        .take(31)
        .collect();
    let base = if clean.trim().is_empty() {
        format!("Sheet{}", index + 1)
    } else {
        clean
    };
    let mut name = base.clone();
    let mut n = 2;
    while taken.iter().any(|t| t.eq_ignore_ascii_case(&name)) {
        let suffix = format!(" {n}");
        name = base
            .chars()
            .take(31 - suffix.chars().count())
            .collect::<String>()
            + &suffix;
        n += 1;
    }
    taken.push(name.clone());
    name
}

/// Fit `(w, h)` into a `max_w × max_h` box keeping its aspect (the web's `fitBox`).
fn fit_box(w: f64, h: f64, max_w: f64, max_h: f64) -> (f64, f64) {
    let ratio = if w > 0.0 && h > 0.0 { w / h } else { 3.0 };
    let (mut width, mut height) = (max_w, max_w / ratio);
    if height > max_h {
        height = max_h;
        width = max_h * ratio;
    }
    (width.round(), height.round())
}

fn base_format() -> Format {
    Format::new().set_font_name(FONT)
}

fn with_num(format: Format, num: Option<&str>) -> Format {
    match num.filter(|n| !n.is_empty()) {
        Some(num) => format.set_num_format(num),
        None => format,
    }
}

/// A value as text, the way JavaScript's `String(v)` reads it.
fn js_string(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Number(n) => match (n.as_i64(), n.as_f64()) {
            (Some(i), _) => i.to_string(),
            (None, Some(f)) if f.fract() == 0.0 && f.abs() < 1e21 => format!("{f:.0}"),
            (None, Some(f)) => f.to_string(),
            _ => n.to_string(),
        },
        Value::Bool(b) => b.to_string(),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

/// Write one value with `format`: a number as a number, null as a styled blank.
fn write_value(
    ws: &mut Worksheet,
    row: u32,
    col: u16,
    v: &Value,
    format: &Format,
) -> Result<(), XlsxError> {
    match v {
        Value::Null => ws.write_blank(row, col, format).map(|_| ()),
        Value::Number(n) => ws
            .write_number_with_format(row, col, n.as_f64().unwrap_or(0.0), format)
            .map(|_| ()),
        other => ws
            .write_string_with_format(row, col, js_string(other), format)
            .map(|_| ()),
    }
}

/// The value `SUM(B8:B9)` comes to over `rows` (data starting on the 1-based
/// `first_row`), cached in the cell for viewers that do not recalculate.
fn sum_result(formula: &str, rows: &[Vec<Value>], first_row: u32) -> Option<String> {
    let inner = formula
        .trim()
        .trim_start_matches('=')
        .strip_prefix("SUM(")?
        .strip_suffix(')')?;
    let (a, b) = inner.split_once(':')?;
    let split = |cell: &str| {
        let at = cell.find(|c: char| c.is_ascii_digit())?;
        Some((col_index(&cell[..at])?, cell[at..].parse::<u32>().ok()?))
    };
    let ((col, from), (col_b, to)) = (split(a)?, split(b)?);
    if col != col_b {
        return None;
    }
    let sum: f64 = (from..=to)
        .filter_map(|r| r.checked_sub(first_row))
        .filter_map(|i| rows.get(i as usize)?.get(col)?.as_f64())
        .sum();
    Some(if sum.fract() == 0.0 && sum.abs() < 1e15 {
        format!("{sum:.0}")
    } else {
        sum.to_string()
    })
}

/// The banner logo as an image the writer embeds: PNG, JPEG, GIF or BMP as it
/// comes, anything else the decoder reads (an org logo is stored as WebP)
/// re-encoded as PNG. Unreadable bytes draw no logo: as on the web, a logo
/// never fails the export.
fn logo_image(bytes: &[u8]) -> Option<Image> {
    Image::new_from_buffer(bytes).ok().or_else(|| {
        let mut png = Vec::new();
        image::load_from_memory(bytes)
            .ok()?
            .write_to(&mut Cursor::new(&mut png), image::ImageFormat::Png)
            .ok()?;
        Image::new_from_buffer(&png).ok()
    })
}

/// Write the workbook `spec` describes; `logo` (PNG, JPEG, WebP, …) is drawn
/// in each sheet's banner.
pub fn write_workbook(spec: &WorkbookSpec, logo: Option<&[u8]>) -> Result<Vec<u8>, XlsxFailure> {
    let colors = Colors::of(&spec.palette)?;
    let logo = logo
        .filter(|b| !b.is_empty())
        .and_then(logo_image)
        .map(|image| {
            let (w, h) = fit_box(image.width(), image.height(), 150.0, 52.0);
            image
                .set_scale_to_size(w, h, true)
                .set_object_movement(ObjectMovement::MoveButDontSizeWithCells)
        });
    let mut wb = Workbook::new();
    wb.set_properties(&DocProperties::new().set_author(spec.creator.as_deref().unwrap_or("Madar")));
    let mut taken = Vec::new();
    for (index, sheet) in spec.sheets.iter().enumerate() {
        let ws = wb.add_worksheet();
        ws.set_name(sheet_name(sheet.name(), index, &mut taken))?;
        match sheet {
            AnySheet::Table(sheet) => build_sheet(ws, sheet, spec.rtl, &colors, logo.as_ref())?,
            AnySheet::Blocks(sheet) => {
                build_block_sheet(ws, sheet, spec.rtl, &colors, logo.as_ref())?
            }
        }
    }
    if spec.sheets.is_empty() {
        wb.add_worksheet();
    }
    Ok(wb.save_to_buffer()?)
}

fn build_sheet(
    ws: &mut Worksheet,
    sheet: &SheetSpec,
    rtl: bool,
    c: &Colors,
    logo: Option<&Image>,
) -> Result<(), XlsxFailure> {
    if sheet.header_row == 0 || sheet.first_data_row <= sheet.header_row {
        return Err(XlsxFailure::Spec(format!(
            "header row {} / first data row {}",
            sheet.header_row, sheet.first_data_row
        )));
    }
    let header_row = sheet.header_row - 1;
    let data_row = sheet.first_data_row - 1;
    ws.set_landscape();
    ws.set_print_fit_to_pages(1, 0);
    ws.set_freeze_panes(data_row, 0)?;
    if rtl {
        ws.set_right_to_left(true);
    }
    let widths: Vec<f64> = sheet
        .columns
        .iter()
        .map(|col| col.width.unwrap_or(DEFAULT_WIDTH))
        .chain(sheet.padding_widths.iter().copied())
        .collect();
    draw_head(
        ws,
        widths,
        &sheet.title,
        &sheet.subtitle,
        &sheet.stats,
        c,
        logo,
    )?;
    draw_table(ws, sheet, header_row, data_row, c)
}

/// Rows 1–6 of every sheet, whichever kind (the web's `drawHead`): the
/// column widths (padded to six), the banner (the title, right-aligned, the
/// logo at its start), the subtitle line and the stat pills. Returns the
/// padded widths.
fn draw_head(
    ws: &mut Worksheet,
    mut widths: Vec<f64>,
    title_text: &str,
    subtitle: &str,
    stats: &[StatSpec],
    c: &Colors,
    logo: Option<&Image>,
) -> Result<Vec<f64>, XlsxFailure> {
    while widths.len() < MIN_COLUMNS {
        widths.push(PAD_WIDTH);
    }
    for (col, width) in widths.iter().enumerate() {
        ws.set_column_width(col as u16, *width)?;
    }
    let last = (widths.len() - 1) as u16;

    // Banner: the title, right-aligned, with the logo at its start.
    ws.set_row_height(0, 60)?;
    let title = base_format()
        .set_font_size(16)
        .set_bold()
        .set_font_color(c.brand)
        .set_align(FormatAlign::Right)
        .set_align(FormatAlign::VerticalCenter)
        .set_indent(2);
    ws.merge_range(0, 0, 0, last, title_text, &title)?;
    if let Some(logo) = logo {
        // The web anchors it at (col 0.2, row 0.3) of A1.
        let x = (0.2 * (widths[0] * 7.0 + 5.0)).round() as u32;
        let y = (0.3 * 60.0 * 4.0 / 3.0_f64).round() as u32;
        ws.insert_image_with_offset(0, 0, logo, x, y)?;
    }
    let sub = base_format()
        .set_font_size(9)
        .set_font_color(c.muted)
        .set_align(FormatAlign::Center)
        .set_align(FormatAlign::VerticalCenter);
    ws.merge_range(1, 0, 1, last, subtitle, &sub)?;
    ws.set_row_height(2, 6)?;

    // Stat pills (rows 4–5).
    let label = base_format()
        .set_font_size(8)
        .set_font_color(c.muted)
        .set_align(FormatAlign::Center);
    for stat in stats {
        let (Some(a), Some(b)) = (col_index(&stat.from_col), col_index(&stat.to_col)) else {
            return Err(XlsxFailure::Spec(format!(
                "stat columns {:?}..{:?}",
                stat.from_col, stat.to_col
            )));
        };
        let (a, b) = (a.min(b) as u16, a.max(b) as u16);
        let value = with_num(
            base_format()
                .set_font_size(12)
                .set_bold()
                .set_font_color(c.accent)
                .set_align(FormatAlign::Center),
            stat.num_fmt.as_deref(),
        );
        if a < b {
            ws.merge_range(3, a, 3, b, &stat.label, &label)?;
            ws.merge_range(4, a, 4, b, "", &value)?;
        } else {
            ws.write_string_with_format(3, a, &stat.label, &label)?;
        }
        write_value(ws, 4, a, &stat.value, &value)?;
    }
    ws.set_row_height(5, 6)?;
    Ok(widths)
}

/// A sheet of tables (the web's `buildBlockSheet`): every sheet's head, then
/// each laid-out row where the host placed it. Portrait, one page wide and
/// as many down as it takes, nothing frozen.
fn build_block_sheet(
    ws: &mut Worksheet,
    sheet: &BlockSheetSpec,
    rtl: bool,
    c: &Colors,
    logo: Option<&Image>,
) -> Result<(), XlsxFailure> {
    if let Some(r) = sheet.rows.iter().find(|r| r.row < FIRST_BLOCK_ROW) {
        return Err(XlsxFailure::Spec(format!(
            "a {:?} row on row {}: rows 1–6 are the head's",
            r.kind, r.row
        )));
    }
    ws.set_portrait();
    ws.set_print_fit_to_pages(1, 0);
    if rtl {
        ws.set_right_to_left(true);
    }
    let widths = draw_head(
        ws,
        sheet.widths.clone(),
        &sheet.title,
        &sheet.subtitle,
        &sheet.stats,
        c,
        logo,
    )?;
    let last = (widths.len() - 1) as u16;

    let font = |size: u8, color: Color| base_format().set_font_size(size).set_font_color(color);
    let fill = |f: Format, color: Color| {
        f.set_background_color(color)
            .set_pattern(FormatPattern::Solid)
    };
    // A table's first column is its row labels, read from the start; the
    // rest are centred like every sheet's values.
    let align = |f: Format, col: usize| {
        if col == 0 {
            f.set_align(FormatAlign::VerticalCenter)
                .set_align(FormatAlign::Left)
                .set_indent(1)
        } else {
            f.set_align(FormatAlign::VerticalCenter)
                .set_align(FormatAlign::Center)
        }
    };
    let num = |row: &BlockRowSpec, col: usize| row.num_fmts.get(col).cloned().flatten();

    for row in &sheet.rows {
        let r = row.row - 1;
        ws.set_row_height(r, row.height)?;
        let text = row.text.as_deref().unwrap_or("");
        match row.kind {
            BlockRowKind::Gap => {}
            BlockRowKind::Group => {
                let band = fill(font(12, c.white).set_bold(), c.accent)
                    .set_align(FormatAlign::VerticalCenter)
                    .set_align(FormatAlign::Left)
                    .set_indent(1);
                ws.merge_range(r, 0, r, last, text, &band)?;
            }
            BlockRowKind::Title => {
                let title = font(12, c.brand)
                    .set_bold()
                    .set_align(FormatAlign::Bottom)
                    .set_align(FormatAlign::Left);
                ws.merge_range(r, 0, r, last, text, &title)?;
                if let Some(note) = row.note.as_deref().filter(|n| !n.is_empty()) {
                    let muted = font(9, c.muted);
                    ws.write_rich_string_with_format(
                        r,
                        0,
                        &[(&title, text), (&muted, note)],
                        &title,
                    )?;
                }
            }
            BlockRowKind::Header => {
                for (col, v) in row.cells.iter().enumerate() {
                    let f = align(fill(font(10, c.white).set_bold(), c.brand), col).set_text_wrap();
                    write_value(ws, r, col as u16, v, &with_num(f, num(row, col).as_deref()))?;
                }
            }
            BlockRowKind::Body => {
                let zebra = if row.zebra { c.zebra } else { c.white };
                for (col, v) in row.cells.iter().enumerate() {
                    let f = align(fill(font(10, c.text), zebra), col);
                    write_value(ws, r, col as u16, v, &with_num(f, num(row, col).as_deref()))?;
                }
            }
            BlockRowKind::Footer => {
                for (col, v) in row.cells.iter().enumerate() {
                    let mut f = align(fill(font(10, c.text).set_bold(), c.white), col);
                    if row.ruled {
                        f = f
                            .set_border_top(FormatBorder::Thin)
                            .set_border_top_color(c.brand);
                    }
                    write_value(ws, r, col as u16, v, &with_num(f, num(row, col).as_deref()))?;
                }
            }
            BlockRowKind::Caption => {
                let caption = font(9, c.muted)
                    .set_align(FormatAlign::Top)
                    .set_align(FormatAlign::Left)
                    .set_text_wrap()
                    .set_indent(1);
                ws.merge_range(r, 0, r, last, text, &caption)?;
            }
        }
    }
    Ok(())
}

/// The rest of a table sheet (`buildSheet`): the header band, zebra data
/// rows and the totals band.
fn draw_table(
    ws: &mut Worksheet,
    sheet: &SheetSpec,
    header_row: u32,
    data_row: u32,
    c: &Colors,
) -> Result<(), XlsxFailure> {
    let ncols = sheet.columns.len();
    let band = |num: Option<&str>| {
        with_num(
            base_format()
                .set_font_size(10)
                .set_bold()
                .set_font_color(c.white)
                .set_background_color(c.brand)
                .set_pattern(FormatPattern::Solid)
                .set_align(FormatAlign::Center)
                .set_align(FormatAlign::VerticalCenter),
            num,
        )
    };
    ws.set_row_height(header_row, 26)?;
    for (col, spec) in sheet.columns.iter().enumerate() {
        ws.write_string_with_format(header_row, col as u16, &spec.header, &band(None))?;
    }

    // Data rows, zebra from the first.
    for (idx, row) in sheet.rows.iter().enumerate() {
        let r = data_row + idx as u32;
        ws.set_row_height(r, 20)?;
        let fill = if idx % 2 == 0 { c.zebra } else { c.white };
        for (col, spec) in sheet.columns.iter().enumerate() {
            let format = with_num(
                base_format()
                    .set_font_size(10)
                    .set_font_color(c.text)
                    .set_background_color(fill)
                    .set_pattern(FormatPattern::Solid)
                    .set_align(FormatAlign::Center)
                    .set_align(FormatAlign::VerticalCenter),
                spec.num_fmt.as_deref(),
            );
            write_value(
                ws,
                r,
                col as u16,
                row.get(col).unwrap_or(&Value::Null),
                &format,
            )?;
        }
    }

    // Totals band.
    if let Some(totals) = sheet.totals_row.as_ref().filter(|_| !sheet.rows.is_empty()) {
        let r = data_row + sheet.rows.len() as u32;
        ws.set_row_height(r, 24)?;
        for col in 0..ncols {
            let format = band(sheet.columns[col].num_fmt.as_deref());
            let cell = totals.get(col).unwrap_or(&Value::Null);
            match cell.get("formula").and_then(Value::as_str) {
                Some(f) => {
                    let mut formula = Formula::new(f);
                    if let Some(result) = sum_result(f, &sheet.rows, sheet.first_data_row) {
                        formula = formula.set_result(result);
                    }
                    ws.write_formula_with_format(r, col as u16, formula, &format)?;
                }
                None => write_value(ws, r, col as u16, cell, &format)?,
            }
        }
    }
    Ok(())
}

/// Every sheet's rows, each read like the web's `readSheet`: rows with at
/// least one value, each from column A up to its last value; a missing cell
/// is `null`, a date `YYYY-MM-DD`, a whole number an integer.
pub fn read_sheets(bytes: &[u8]) -> Result<Vec<SheetRows>, XlsxFailure> {
    use calamine::Reader;
    let mut wb = calamine::open_workbook_auto_from_rs(Cursor::new(bytes.to_vec()))
        .map_err(|e| XlsxFailure::Read(e.to_string()))?;
    let mut out = Vec::new();
    for name in wb.sheet_names() {
        let range = wb
            .worksheet_range(&name)
            .map_err(|e| XlsxFailure::Read(e.to_string()))?;
        let lead = range.start().map_or(0, |(_, c)| c as usize);
        let mut rows = Vec::new();
        for row in range.rows() {
            let mut values: Vec<Value> = std::iter::repeat_n(Value::Null, lead)
                .chain(row.iter().map(cell_json))
                .collect();
            while values.last().is_some_and(Value::is_null) {
                values.pop();
            }
            if !values.is_empty() {
                rows.push(values);
            }
        }
        out.push(SheetRows { name, rows });
    }
    Ok(out)
}

/// One read cell as JSON (the web's `cellValue`).
fn cell_json(cell: &calamine::Data) -> Value {
    use calamine::Data;
    match cell {
        Data::Empty => Value::Null,
        Data::String(s) => Value::String(s.clone()),
        Data::Bool(b) => Value::Bool(*b),
        Data::Int(i) => Value::from(*i),
        Data::Float(f) => {
            if f.fract() == 0.0 && f.abs() < 9_007_199_254_740_992.0 {
                Value::from(*f as i64)
            } else {
                serde_json::Number::from_f64(*f).map_or(Value::Null, Value::Number)
            }
        }
        Data::DateTime(dt) => match dt.as_datetime() {
            Some(t) => Value::String(t.format("%Y-%m-%d").to_string()),
            None => Value::from(dt.as_f64()),
        },
        Data::DateTimeIso(s) => Value::String(s.chars().take(10).collect()),
        Data::DurationIso(s) => Value::String(s.clone()),
        Data::Error(e) => Value::String(e.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use calamine::Reader;
    use serde_json::json;
    use std::io::Read;

    /// What dashboard_core's `DashExporter.workbookSpec(...).toJson()` writes
    /// for a two-order sheet (Cairo, money, a date-time, a bool, totals). The
    /// first order's date is 2026-06-16 01:30 in Cairo, as
    /// `toExcelDateSerial` writes it.
    fn orders() -> Value {
        json!({
            "creator": "Madar",
            "logo_url": null,
            "palette": { "brand": "FF14181E", "accent": "FF14181E", "white": "FFFFFFFF",
                         "zebra": "FFEDF2F3", "border": "FFD7E0E1", "text": "FF14181E",
                         "muted": "FF76828B" },
            "sheets": [{
                "name": "Orders SeptOct",
                "title": "Orders",
                "subtitle": "1–30 Sep  ·  Heliopolis  ·  Generated: 08 Oct 2026, 03:15 PM",
                "columns": [
                    { "header": "Order", "width": 12, "num_fmt": null },
                    { "header": "Total", "width": 20, "num_fmt": "#,##0.00 \"EGP\"" },
                    { "header": "Items", "width": 20, "num_fmt": "#,##0" },
                    { "header": "Placed", "width": 20, "num_fmt": "dd mmm yyyy hh:mm AM/PM" },
                    { "header": "Paid", "width": 20, "num_fmt": null }
                ],
                "padding_widths": [18],
                "stats": [
                    { "label": "Orders", "value": 2, "from_col": "A", "to_col": "B", "num_fmt": "#,##0" },
                    { "label": "Revenue", "value": 165.5, "from_col": "C", "to_col": "D",
                      "num_fmt": "#,##0.00 \"EGP\"" }
                ],
                "rows": [
                    ["HEL-0001", 125.5, 2, 46189.0625, "✓"],
                    ["HEL-0002", 40, 3, null, "—"]
                ],
                "totals_row": ["TOTALS", { "formula": "SUM(B8:B9)" }, { "formula": "SUM(C8:C9)" }, "", ""],
                "header_row": 7,
                "first_data_row": 8
            }]
        })
    }

    fn spec(v: Value) -> WorkbookSpec {
        serde_json::from_value(v).unwrap()
    }

    fn part(bytes: &[u8], name: &str) -> String {
        let mut zip = zip::ZipArchive::new(Cursor::new(bytes.to_vec())).unwrap();
        let mut f = zip.by_name(name).unwrap();
        let mut s = String::new();
        f.read_to_string(&mut s).unwrap();
        s
    }

    #[test]
    fn names_letters_and_boxes() {
        let mut taken = Vec::new();
        assert_eq!(
            sheet_name("Orders: Sept/Oct", 0, &mut taken),
            "Orders SeptOct"
        );
        assert_eq!(
            sheet_name("Orders: Sept/Oct", 1, &mut taken),
            "Orders SeptOct 2"
        );
        assert_eq!(sheet_name("", 2, &mut taken), "Sheet3");
        assert_eq!(
            sheet_name(&"ا".repeat(40), 3, &mut taken).chars().count(),
            31
        );
        assert_eq!(col_index("A"), Some(0));
        assert_eq!(col_index("Z"), Some(25));
        assert_eq!(col_index("AA"), Some(26));
        assert_eq!(col_index("1"), None);
        assert_eq!(fit_box(400.0, 120.0, 150.0, 52.0), (150.0, 45.0));
        assert_eq!(fit_box(100.0, 100.0, 150.0, 52.0), (52.0, 52.0));
        let rows = vec![vec![json!("a"), json!(1.5)], vec![json!("b"), json!(2)]];
        assert_eq!(sum_result("SUM(B8:B9)", &rows, 8).as_deref(), Some("3.5"));
        assert_eq!(sum_result("AVERAGE(B8:B9)", &rows, 8), None);
        assert_eq!(js_string(&json!(2.0)), "2");
    }

    #[test]
    fn the_workbook_round_trips_with_the_webs_layout() {
        let bytes = write_workbook(&spec(orders()), None).unwrap();
        let sheets = read_sheets(&bytes).unwrap();
        assert_eq!(sheets.len(), 1);
        assert_eq!(sheets[0].name, "Orders SeptOct");
        let rows = &sheets[0].rows;
        // Row 1 title, row 2 subtitle, rows 4–5 stats (rows 3 and 6 are empty).
        assert_eq!(rows[0], vec![json!("Orders")]);
        assert_eq!(
            rows[1],
            vec![json!(
                "1–30 Sep  ·  Heliopolis  ·  Generated: 08 Oct 2026, 03:15 PM"
            )]
        );
        assert_eq!(
            rows[2],
            vec![json!("Orders"), Value::Null, json!("Revenue")]
        );
        assert_eq!(rows[3], vec![json!(2), Value::Null, json!(165.5)]);
        assert_eq!(
            rows[4],
            vec![
                json!("Order"),
                json!("Total"),
                json!("Items"),
                json!("Placed"),
                json!("Paid")
            ]
        );
        assert_eq!(
            rows[5],
            vec![
                json!("HEL-0001"),
                json!(125.5),
                json!(2),
                json!("2026-06-16"),
                json!("✓")
            ]
        );
        assert_eq!(
            rows[6],
            vec![
                json!("HEL-0002"),
                json!(40),
                json!(3),
                Value::Null,
                json!("—")
            ]
        );
        // Totals: the label, then the SUMs with their values cached.
        assert_eq!(rows[7], vec![json!("TOTALS"), json!(165.5), json!(5)]);
        assert_eq!(rows.len(), 8);

        let mut wb = calamine::open_workbook_auto_from_rs(Cursor::new(bytes.clone())).unwrap();
        let formulas = wb.worksheet_formula("Orders SeptOct").unwrap();
        assert!(formulas.used_cells().any(|(_, _, f)| f == "SUM(B8:B9)"));

        let xml = part(&bytes, "xl/worksheets/sheet1.xml");
        assert!(
            xml.contains(r#"ySplit="7""#),
            "the header and banner stay frozen"
        );
        assert!(!xml.contains("rightToLeft"));
        assert!(
            xml.contains(r#"<mergeCell ref="A1:F1"/>"#),
            "the banner spans the padded width"
        );
        assert!(xml.contains(r#"<mergeCell ref="A4:B4"/>"#));
        assert!(xml.contains(r#"<mergeCell ref="C5:D5"/>"#));
        assert!(xml.contains(r#"orientation="landscape""#));
        assert!(xml.contains(r#"<pageSetUpPr fitToPage="1"/>"#));
        let styles = part(&bytes, "xl/styles.xml");
        assert!(styles.contains("#,##0.00 &quot;EGP&quot;"));
        assert!(styles.contains("dd mmm yyyy hh:mm AM/PM"));
        assert!(styles.contains("FF14181E"), "the ink band");
        assert!(!styles.contains("FF0D6273"), "no teal left");
        assert!(styles.contains("FFEDF2F3"), "the zebra rows");
        assert!(styles.contains("IBM Plex Sans Arabic"));
        assert!(part(&bytes, "docProps/core.xml").contains("<dc:creator>Madar</dc:creator>"));
    }

    #[test]
    fn an_arabic_export_is_right_to_left_with_its_logo() {
        let mut v = orders();
        v["rtl"] = json!(true);
        v["sheets"][0]["title"] = json!("الطلبات");
        v["sheets"][0]["totals_row"][0] = json!("الإجماليات");
        // A 2×1 PNG.
        let png: Vec<u8> = vec![
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48,
            0x44, 0x52, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00,
            0x00, 0x7B, 0x40, 0xE8, 0xDD, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78,
            0x9C, 0x63, 0xE0, 0x4D, 0x2A, 0x06, 0x22, 0x00, 0x05, 0x69, 0x01, 0xC5, 0xD9, 0x13,
            0xDF, 0xEC, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ];
        let bytes = write_workbook(&spec(v), Some(&png)).unwrap();
        let xml = part(&bytes, "xl/worksheets/sheet1.xml");
        assert!(xml.contains(r#"rightToLeft="1""#));
        assert!(xml.contains("<drawing "), "the logo is drawn in the banner");
        let rows = &read_sheets(&bytes).unwrap()[0].rows;
        assert_eq!(rows[0], vec![json!("الطلبات")]);
        assert_eq!(rows.last().unwrap()[0], json!("الإجماليات"));
    }

    /// An org's logo is stored as WebP, which the writer cannot embed: it is
    /// drawn as a PNG, and bytes no decoder reads draw no logo instead of
    /// failing the export (every branded shop's exports used to fail).
    #[test]
    fn a_webp_logo_is_drawn_and_an_unreadable_one_is_skipped() {
        let mut webp = Vec::new();
        image::DynamicImage::ImageRgba8(image::RgbaImage::from_pixel(
            40,
            12,
            image::Rgba([13, 98, 115, 255]),
        ))
        .write_to(&mut Cursor::new(&mut webp), image::ImageFormat::WebP)
        .unwrap();
        assert_eq!(&webp[8..12], b"WEBP");
        let bytes = write_workbook(&spec(orders()), Some(&webp)).unwrap();
        assert!(part(&bytes, "xl/worksheets/sheet1.xml").contains("<drawing "));
        let mut media = Vec::new();
        zip::ZipArchive::new(Cursor::new(bytes))
            .unwrap()
            .by_name("xl/media/image1.png")
            .unwrap()
            .read_to_end(&mut media)
            .unwrap();
        assert!(media.starts_with(b"\x89PNG"));

        let bytes = write_workbook(&spec(orders()), Some(b"<html>not an image</html>")).unwrap();
        assert!(!part(&bytes, "xl/worksheets/sheet1.xml").contains("<drawing "));
        assert_eq!(read_sheets(&bytes).unwrap()[0].rows.len(), 8);
    }

    #[test]
    fn a_bad_spec_is_refused_and_an_empty_one_still_writes() {
        let mut bad = orders();
        bad["palette"]["brand"] = json!("teal");
        assert!(matches!(
            write_workbook(&spec(bad), None),
            Err(XlsxFailure::Spec(_))
        ));
        let mut bad = orders();
        bad["sheets"][0]["stats"][0]["from_col"] = json!("1");
        assert!(matches!(
            write_workbook(&spec(bad), None),
            Err(XlsxFailure::Spec(_))
        ));
        let empty = write_workbook(&WorkbookSpec::default(), None).unwrap();
        assert_eq!(
            read_sheets(&empty).unwrap()[0].rows,
            Vec::<Vec<Value>>::new()
        );
        assert!(matches!(
            read_sheets(b"not a workbook"),
            Err(XlsxFailure::Read(_))
        ));
        // No rows and no stats: the banner, the subtitle and the header.
        let mut bare = orders();
        bare["sheets"][0]["rows"] = json!([]);
        bare["sheets"][0]["stats"] = json!([]);
        let rows = &read_sheets(&write_workbook(&spec(bare), None).unwrap()).unwrap()[0].rows;
        assert_eq!(rows.len(), 3);
    }

    /// What dashboard_core's `DashExporter.workbookSpec(...).toJson()` writes
    /// for the web's own "a sheet of tables" test sheet (excel.test.ts): one
    /// group, one table with a note, two body rows, a cost footer, a caption.
    fn recipe_book() -> Value {
        json!({
            "creator": "Madar",
            "logo_url": null,
            "palette": { "brand": "FF14181E", "accent": "FF14181E", "white": "FFFFFFFF",
                         "zebra": "FFEDF2F3", "border": "FFD7E0E1", "text": "FF14181E",
                         "muted": "FF76828B" },
            "sheets": [{
                "kind": "blocks",
                "name": "Recipes",
                "title": "Recipes",
                "subtitle": "Generated: 08 Oct 2026, 10:30 AM",
                "widths": [30.0, 8.0, 14.0, 14.0, 18.0, 18.0],
                "stats": [{ "label": "Items", "value": 1, "from_col": "A", "to_col": "D",
                            "num_fmt": "#,##0" }],
                "rows": [
                    { "kind": "group", "row": 7, "height": 24, "text": "Coffee" },
                    { "kind": "gap", "row": 8, "height": 6 },
                    { "kind": "title", "row": 9, "height": 22, "text": "Latte",
                      "note": "   Follows Flat white" },
                    { "kind": "header", "row": 10, "height": 22,
                      "cells": ["Ingredient", "Unit", "Small", "Large"],
                      "num_fmts": [null, null, null, null] },
                    { "kind": "body", "row": 11, "height": 20,
                      "cells": ["Espresso beans", "g", 18, 18.5],
                      "num_fmts": [null, null, null, null], "zebra": true },
                    { "kind": "body", "row": 12, "height": 20,
                      "cells": ["Vanilla syrup", "ml", null, 20],
                      "num_fmts": [null, null, null, null], "zebra": false },
                    { "kind": "footer", "row": 13, "height": 20,
                      "cells": ["Cost", null, 2.05, 2.85],
                      "num_fmts": [null, null, "#,##0.00 \"EGP\"", "#,##0.00 \"EGP\""],
                      "ruled": true },
                    { "kind": "caption", "row": 14, "height": 18,
                      "text": "How it's made: 1. Pull a double shot" },
                    { "kind": "gap", "row": 15, "height": 10 }
                ]
            }]
        })
    }

    /// One cell's value by its A1 address, read back with calamine.
    fn value_at(bytes: &[u8], sheet: &str, cell: &str) -> Option<calamine::Data> {
        let (col, row) = a1(cell);
        let mut wb = calamine::open_workbook_auto_from_rs(Cursor::new(bytes.to_vec())).unwrap();
        let range = wb.worksheet_range(sheet).unwrap();
        range
            .get_value((row, col))
            .cloned()
            .filter(|d| *d != calamine::Data::Empty)
    }

    /// `C11` → (column 2, row 10), zero-based.
    fn a1(cell: &str) -> (u32, u32) {
        let at = cell.find(|c: char| c.is_ascii_digit()).unwrap();
        (
            col_index(&cell[..at]).unwrap() as u32,
            cell[at..].parse::<u32>().unwrap() - 1,
        )
    }

    /// The part of `xml` inside `<name …>` … `</name>`.
    fn section(xml: &str, name: &str) -> String {
        let open = xml
            .find(&format!("<{name}"))
            .unwrap_or_else(|| panic!("no <{name}>"));
        let body = open + xml[open..].find('>').unwrap() + 1;
        let close = xml[body..]
            .find(&format!("</{name}>"))
            .map_or(xml.len(), |i| body + i);
        xml[body..close].to_string()
    }

    fn attr(tag: &str, name: &str) -> Option<String> {
        let key = format!(r#" {name}=""#);
        let at = tag.find(&key)? + key.len();
        Some(tag[at..at + tag[at..].find('"')?].to_string())
    }

    /// How one cell is drawn, from the written XML: its `<xf>` (alignment),
    /// font, fill and border elements and its number format code.
    #[derive(Debug)]
    struct Drawn {
        xf: String,
        font: String,
        fill: String,
        border: String,
        num_fmt: String,
    }

    fn drawn(bytes: &[u8], sheet_part: &str, cell: &str) -> Drawn {
        let xml = part(bytes, sheet_part);
        let at = xml
            .find(&format!(r#"<c r="{cell}""#))
            .unwrap_or_else(|| panic!("no cell {cell}"));
        let tag = &xml[at..at + xml[at..].find('>').unwrap()];
        let s: usize = attr(tag, "s").map_or(0, |v| v.parse().unwrap());
        let styles = part(bytes, "xl/styles.xml");
        let xfs: Vec<String> = section(&styles, "cellXfs")
            .split("<xf ")
            .skip(1)
            .map(|x| format!("<xf {x}"))
            .collect();
        let xf = xfs[s].clone();
        let nth = |list: &str, close: &str, id: &str| -> String {
            let i: usize = attr(&xf, id).unwrap().parse().unwrap();
            section(&styles, list)
                .split(close)
                .nth(i)
                .unwrap()
                .to_string()
        };
        let num_id = attr(&xf, "numFmtId").unwrap();
        let num_fmt = if num_id == "0" {
            "General".to_string()
        } else {
            section(&styles, "numFmts")
                .split("<numFmt ")
                .find(|f| attr(&format!(" {f}"), "numFmtId").as_deref() == Some(&num_id))
                .and_then(|f| attr(&format!(" {f}"), "formatCode"))
                .unwrap_or(num_id)
                .replace("&quot;", "\"")
        };
        Drawn {
            font: nth("fonts", "</font>", "fontId"),
            fill: nth("fills", "</fill>", "fillId"),
            border: nth("borders", "</border>", "borderId"),
            num_fmt,
            xf,
        }
    }

    /// excel.test.ts "draws every sheet's head, then the group band and each
    /// table in order": the same cells, values and styles.
    #[test]
    fn a_sheet_of_tables_is_drawn_as_the_webs_block_sheet() {
        let bytes = write_workbook(&spec(recipe_book()), None).unwrap();
        let sheets = read_sheets(&bytes).unwrap();
        assert_eq!(sheets.len(), 1);
        assert_eq!(sheets[0].name, "Recipes");
        let at = |cell: &str| value_at(&bytes, "Recipes", cell);
        let d = |cell: &str| drawn(&bytes, "xl/worksheets/sheet1.xml", cell);
        use calamine::Data;
        let s = |v: &str| Some(Data::String(v.into()));

        // Every sheet's head.
        assert_eq!(at("A1"), s("Recipes"));
        assert_eq!(at("A2"), s("Generated: 08 Oct 2026, 10:30 AM"));
        assert_eq!(at("A4"), s("Items"));
        assert_eq!(at("A5"), Some(Data::Float(1.0)));

        // The group band.
        assert_eq!(at("A7"), s("Coffee"));
        assert!(d("A7").fill.contains(r#"rgb="FF14181E""#), "{:?}", d("A7"));
        assert!(d("A7").font.contains("<b/>") && d("A7").font.contains(r#"<sz val="12"/>"#));
        assert!(d("A7").font.contains(r#"rgb="FFFFFFFF""#));

        // The title, the note muted after it (one rich string).
        assert_eq!(at("A9"), s("Latte   Follows Flat white"));
        let shared = part(&bytes, "xl/sharedStrings.xml");
        let runs: Vec<&str> = shared.split("<r>").skip(1).collect();
        let latte = runs
            .iter()
            .find(|r| r.contains(">Latte</t>"))
            .expect("a run for the title");
        assert!(latte.contains("<b/>") && latte.contains(r#"<sz val="12"/>"#));
        assert!(latte.contains(r#"rgb="FF14181E""#));
        let note = runs
            .iter()
            .find(|r| r.contains("   Follows Flat white</t>"))
            .expect("a run for the note, its three spaces kept");
        assert!(!note.contains("<b/>") && note.contains(r#"<sz val="9"/>"#));
        assert!(note.contains(r#"rgb="FF76828B""#));

        // The header band.
        let header: Vec<_> = ["A10", "B10", "C10", "D10"].iter().map(|c| at(c)).collect();
        assert_eq!(header, [s("Ingredient"), s("Unit"), s("Small"), s("Large")]);
        assert!(d("A10").fill.contains(r#"rgb="FF14181E""#));
        assert!(d("C10").xf.contains(r#"wrapText="1""#));

        // Body rows: quantities as they are, zebra from the first.
        let body: Vec<_> = ["A11", "B11", "C11", "D11"].iter().map(|c| at(c)).collect();
        assert_eq!(
            body,
            [
                s("Espresso beans"),
                s("g"),
                Some(Data::Float(18.0)),
                Some(Data::Float(18.5))
            ]
        );
        assert_eq!(d("C11").num_fmt, "General", "no fixed decimals");
        assert_eq!(at("C12"), None, "a size without the line is a blank");
        assert!(
            d("C12").fill.contains(r#"rgb="FFFFFFFF""#),
            "still striped (white)"
        );
        assert!(d("C11").fill.contains(r#"rgb="FFEDF2F3""#));

        // The footer: bold, money ÷ 100 already, ruled above.
        assert_eq!(at("A13"), s("Cost"));
        assert_eq!(at("C13"), Some(Data::Float(2.05)));
        assert_eq!(d("C13").num_fmt, r#"#,##0.00 "EGP""#);
        assert!(
            d("C13")
                .border
                .contains(r#"<top style="thin"><color rgb="FF14181E"/>"#),
            "{:?}",
            d("C13")
        );
        assert!(d("A13").font.contains("<b/>"));

        // The caption, wrapped across the sheet.
        assert_eq!(at("A14"), s("How it's made: 1. Pull a double shot"));
        assert!(d("A14").xf.contains(r#"wrapText="1""#));

        // The label column reads from the start, the values are centred.
        assert!(d("A11").xf.contains(r#"horizontal="left""#));
        assert!(d("A11").xf.contains(r#"indent="1""#));
        assert!(d("C11").xf.contains(r#"horizontal="center""#));

        let xml = part(&bytes, "xl/worksheets/sheet1.xml");
        for merge in ["A1:F1", "A2:F2", "A7:F7", "A9:F9", "A14:F14"] {
            assert!(
                xml.contains(&format!(r#"<mergeCell ref="{merge}"/>"#)),
                "{merge}"
            );
        }
        assert!(
            xml.contains(r#"<mergeCell ref="A4:D4"/>"#),
            "the pill spans the table"
        );
        // The spec's heights (24, 6, 22, 22, 20, 18, 10 pt), as the writer
        // stores them: in whole pixels (22 pt is 29 px, 21.75 pt), as every
        // sheet's rows already are (the header's 26 is 26.25).
        for (row, ht) in [
            (7, "24"),
            (8, "6"),
            (9, "21.75"),
            (10, "21.75"),
            (11, "20.25"),
            (14, "18"),
            (15, "9.75"),
        ] {
            let at = xml
                .find(&format!(r#"<row r="{row}" "#))
                .unwrap_or_else(|| panic!("row {row}"));
            let tag = &xml[at..at + xml[at..].find('>').unwrap()];
            assert_eq!(attr(tag, "ht").as_deref(), Some(ht), "row {row}");
        }
        assert!(xml.contains(r#"orientation="portrait""#));
        assert!(xml.contains(r#"<pageSetUpPr fitToPage="1"/>"#));
        assert!(
            xml.contains(r#"fitToHeight="0""#),
            "as many pages down as it takes"
        );
        assert!(!xml.contains("<pane "), "nothing frozen");
        assert!(
            xml.contains(r#"<col min="1" max="1" width="30.7109375""#),
            "the label column"
        );
    }

    /// A book is two sheets: the tables, then the flat lines (a table sheet,
    /// drawn exactly as before).
    #[test]
    fn a_book_and_a_table_sheet_in_one_workbook() {
        let mut v = recipe_book();
        let table = orders()["sheets"][0].clone();
        v["sheets"].as_array_mut().unwrap().push(table);
        // A title with no note is a plain string.
        v["sheets"][0]["rows"][2]
            .as_object_mut()
            .unwrap()
            .remove("note");
        let bytes = write_workbook(&spec(v), None).unwrap();
        let sheets = read_sheets(&bytes).unwrap();
        assert_eq!(
            sheets.iter().map(|s| s.name.as_str()).collect::<Vec<_>>(),
            ["Recipes", "Orders SeptOct"]
        );
        assert_eq!(sheets[1].rows.len(), 8, "the table sheet is unchanged");
        assert_eq!(
            value_at(&bytes, "Recipes", "A9"),
            Some(calamine::Data::String("Latte".into()))
        );
        assert!(
            !part(&bytes, "xl/sharedStrings.xml").contains("<r>"),
            "no rich text"
        );
        let tables = part(&bytes, "xl/worksheets/sheet1.xml");
        assert!(!tables.contains("<pane "));
        let orders = part(&bytes, "xl/worksheets/sheet2.xml");
        assert!(orders.contains(r#"ySplit="7""#) && orders.contains(r#"orientation="landscape""#));
    }

    #[test]
    fn a_bad_sheet_of_tables_is_refused() {
        let mut unknown = recipe_book();
        unknown["sheets"][0]["kind"] = json!("chart");
        assert!(serde_json::from_value::<WorkbookSpec>(unknown).is_err());
        let mut row = recipe_book();
        row["sheets"][0]["rows"][0]["kind"] = json!("banner");
        assert!(serde_json::from_value::<WorkbookSpec>(row).is_err());
        // Row 6 is the head's.
        let mut early = recipe_book();
        early["sheets"][0]["rows"][0]["row"] = json!(6);
        assert!(matches!(
            write_workbook(&spec(early), None),
            Err(XlsxFailure::Spec(_))
        ));
        // A sheet with no kind is a table sheet, as every sheet before it.
        let mut table = orders();
        table["sheets"][0]["kind"] = json!("table");
        assert_eq!(
            read_sheets(&write_workbook(&spec(table), None).unwrap()).unwrap()[0]
                .rows
                .len(),
            8
        );
    }

    /// An import file someone made: two sheets, a gap before column A's
    /// data, a blank row, a date and a formula.
    /// Every cell is set in the dashboard's typeface (owner, 2026-11-25), as
    /// the web's EXPORT_FONT.
    #[test]
    fn every_cell_is_set_in_ibm_plex_sans_arabic() {
        let spec: WorkbookSpec = serde_json::from_value(json!({
            "sheets": [{ "name": "S", "title": "S", "subtitle": "s",
                "columns": [{ "header": "A", "width": 20 }], "rows": [["x"]],
                "header_row": 7, "first_data_row": 8 }]
        }))
        .unwrap();
        let bytes = write_workbook(&spec, None).unwrap();
        let styles = part(&bytes, "xl/styles.xml");
        assert!(
            styles.contains(r#"<name val="IBM Plex Sans Arabic"/>"#),
            "{styles}"
        );
    }

    #[test]
    fn an_import_reads_like_the_webs_read_sheet() {
        let mut wb = Workbook::new();
        let ws = wb.add_worksheet().set_name("People").unwrap();
        ws.write_string(1, 1, "Name").unwrap();
        ws.write_string(1, 2, "Salary").unwrap();
        ws.write_string(3, 1, "منى").unwrap();
        ws.write_number(3, 2, 6500).unwrap();
        ws.write_formula(3, 3, Formula::new("C4*2").set_result("13000"))
            .unwrap();
        let date = Format::new().set_num_format("yyyy-mm-dd");
        ws.write_number_with_format(3, 4, 46280.0, &date).unwrap();
        wb.add_worksheet()
            .set_name("Notes")
            .unwrap()
            .write_string(0, 0, "ok")
            .unwrap();
        let bytes = wb.save_to_buffer().unwrap();
        let sheets = read_sheets(&bytes).unwrap();
        assert_eq!(
            sheets,
            vec![
                SheetRows {
                    name: "People".into(),
                    rows: vec![
                        vec![Value::Null, json!("Name"), json!("Salary")],
                        vec![
                            Value::Null,
                            json!("منى"),
                            json!(6500),
                            json!(13000),
                            json!("2026-09-15")
                        ],
                    ],
                },
                SheetRows {
                    name: "Notes".into(),
                    rows: vec![vec![json!("ok")]],
                },
            ]
        );
    }
}
