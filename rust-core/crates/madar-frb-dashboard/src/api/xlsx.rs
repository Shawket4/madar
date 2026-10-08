//! Spreadsheet export / import on the dashboard bridge. Binding code only:
//! the workbook itself is `crate::xlsx` (the web's `src/lib/excel.ts` layout).
use crate::api::error::MadarError;
use crate::xlsx::{self as engine, XlsxFailure};

/// Write the workbook `spec_json` describes (dashboard_core's
/// `WorkbookSpec.toJson()`, laid out the way the web's excel.ts lays it out,
/// plus an optional `"rtl": true`; see `crate::xlsx`) and return the `.xlsx`
/// bytes. `logo` is a PNG or JPEG drawn in each sheet's banner.
pub fn xlsx_write(spec_json: String, logo: Option<Vec<u8>>) -> Result<Vec<u8>, MadarError> {
    let spec: engine::WorkbookSpec =
        serde_json::from_str(&spec_json).map_err(|e| MadarError::Validation {
            field: "spec".into(),
            detail: e.to_string(),
        })?;
    engine::write_workbook(&spec, logo.as_deref()).map_err(to_error)
}

/// Every sheet of an `.xlsx` (or `.xls` / `.ods`) file, as JSON:
/// `[{"name": "…", "rows": [[cell, …], …]}, …]`, each read like the web's
/// `readSheet` (a date cell as `YYYY-MM-DD`, a formula as its result).
pub fn xlsx_read(bytes: Vec<u8>) -> Result<String, MadarError> {
    let sheets = engine::read_sheets(&bytes).map_err(to_error)?;
    serde_json::to_string(&sheets).map_err(|e| MadarError::Internal {
        detail: e.to_string(),
    })
}

fn to_error(e: XlsxFailure) -> MadarError {
    match e {
        XlsxFailure::Spec(detail) => MadarError::Validation {
            field: "spec".into(),
            detail,
        },
        XlsxFailure::Read(detail) => MadarError::Validation {
            field: "file".into(),
            detail,
        },
        XlsxFailure::Write(detail) => MadarError::Internal { detail },
    }
}
