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
//!   "palette": { "brand": "FF0D6273", "accent": "FF2E94A6", "white": "FFFFFFFF",
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
//! The import reads every sheet the way the web's `readSheet` reads one
//! (`features/dawam/people.ts`): non-empty rows only, each from column A up
//! to its last value, a date cell as `YYYY-MM-DD`, a formula as its result.

use std::io::Cursor;

use rust_xlsxwriter::{
    Color, DocProperties, Format, FormatAlign, FormatPattern, Formula, Image, ObjectMovement,
    Workbook, Worksheet, XlsxError,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;

const FONT: &str = "Calibri";
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
    pub sheets: Vec<SheetSpec>,
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
        Palette {
            brand: "FF0D6273".into(),
            accent: "FF2E94A6".into(),
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

/// `FF0D6273` (ARGB) → the RGB colour.
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

/// Write the workbook `spec` describes; `logo` is a PNG/JPEG drawn in each
/// sheet's banner.
pub fn write_workbook(spec: &WorkbookSpec, logo: Option<&[u8]>) -> Result<Vec<u8>, XlsxFailure> {
    let colors = Colors::of(&spec.palette)?;
    let logo = match logo.filter(|b| !b.is_empty()) {
        Some(bytes) => {
            let image = Image::new_from_buffer(bytes)?;
            let (w, h) = fit_box(image.width(), image.height(), 150.0, 52.0);
            Some(
                image
                    .set_scale_to_size(w, h, true)
                    .set_object_movement(ObjectMovement::MoveButDontSizeWithCells),
            )
        }
        None => None,
    };
    let mut wb = Workbook::new();
    wb.set_properties(&DocProperties::new().set_author(spec.creator.as_deref().unwrap_or("Madar")));
    let mut taken = Vec::new();
    for (index, sheet) in spec.sheets.iter().enumerate() {
        let ws = wb.add_worksheet();
        ws.set_name(sheet_name(&sheet.name, index, &mut taken))?;
        build_sheet(ws, sheet, spec.rtl, &colors, logo.as_ref())?;
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

    let ncols = sheet.columns.len();
    let mut widths: Vec<f64> = sheet
        .columns
        .iter()
        .map(|col| col.width.unwrap_or(DEFAULT_WIDTH))
        .chain(sheet.padding_widths.iter().copied())
        .collect();
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
    ws.merge_range(0, 0, 0, last, &sheet.title, &title)?;
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
    ws.merge_range(1, 0, 1, last, &sheet.subtitle, &sub)?;
    ws.set_row_height(2, 6)?;

    // Stat pills (rows 4–5).
    let label = base_format()
        .set_font_size(8)
        .set_font_color(c.muted)
        .set_align(FormatAlign::Center);
    for stat in &sheet.stats {
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

    // Header.
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
            "palette": { "brand": "FF0D6273", "accent": "FF2E94A6", "white": "FFFFFFFF",
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
        assert!(styles.contains("FF0D6273"), "the brand band");
        assert!(styles.contains("FFEDF2F3"), "the zebra rows");
        assert!(styles.contains("Calibri"));
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

    /// An import file someone made: two sheets, a gap before column A's
    /// data, a blank row, a date and a formula.
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
