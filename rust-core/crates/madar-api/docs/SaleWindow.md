# SaleWindow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | `null` = every branch. | [optional]
**ends_at** | Option<**String**> |  | [optional]
**id** | Option<**uuid::Uuid**> | Ignored on write (windows are replaced as a set). | [optional]
**starts_at** | Option<**String**> | \"HH:MM\"; with `ends_at`, or neither (the whole day). `ends_at` before `starts_at` crosses midnight: the part after midnight belongs to the day the window started (its weekday and date range). | [optional]
**valid_from** | Option<**chrono::NaiveDate**> | Optional date range, inclusive, judged on the day the window started. | [optional]
**valid_to** | Option<**chrono::NaiveDate**> |  | [optional]
**weekdays** | Option<**i32**> | bit0 = Sunday … bit6 = Saturday; 127 = every day (the default). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


