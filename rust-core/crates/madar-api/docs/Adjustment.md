# Adjustment

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_piastres** | Option<**i64**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**effective_date** | **chrono::NaiveDate** | The month it lands in (the first day of a recurring line, AD-1/AD-3). | 
**employee_id** | **uuid::Uuid** |  | 
**employee_name** | **String** |  | 
**ends_on** | Option<**chrono::NaiveDate**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**kind** | **String** | `bonus` · `deduction` | 
**original_amount_piastres** | Option<**i64**> |  | [optional]
**overridden_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**percent_of_base** | Option<**f64**> |  | [optional]
**reason** | **String** |  | 
**reason_code** | Option<**String**> | A rule-made line's reason as a code and its figures (`late` `{minutes}`, `absent_no_punch`, …), the payslip breakdown's own, so a client words it in its language (AT-13, E2E B-PAY-4). Null for a bonus and for a manual line (its `reason` is what was typed). | [optional]
**reason_vars** | Option<**serde_json::Value**> |  | [optional]
**recurring** | **bool** |  | 
**source** | **String** |  | 
**status** | **String** | `pending` (waits for the owner) · `approved` · `rejected` | 
**stop_reason** | Option<**String**> |  | [optional]
**stopped_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**value_piastres** | **i64** | A percent line valued against the salary, in piastres — the server's figure (AT-3); equals `amount_piastres` for a flat line. | 
**waived_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | A rule-made deduction the manager forgave: shown, counted for nothing (AD-6/AD-8). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


