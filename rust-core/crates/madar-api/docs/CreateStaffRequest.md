# CreateStaffRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**attendance_record_id** | Option<**uuid::Uuid**> | `correction` only — the record whose punch is wrong. | [optional]
**employee_id** | Option<**uuid::Uuid**> | Admin-only. Omitted on `/staff/me/_*`, where it is always the caller. | [optional]
**end_date** | Option<**chrono::NaiveDate**> |  | [optional]
**from_time** | Option<**String**> | Branch-local wall clock. | [optional]
**is_half_day** | Option<**bool**> |  | [optional]
**is_paid** | Option<**bool**> | Only when the request is approved as it is filed (the filer holds `hr.requests.self_approve`): leave paid or unpaid, an excuse's pay. Omitted: leave is paid, an excuse follows the rule. | [optional]
**kind** | **String** | One of `leave`, `late_arrival`, `early_departure`, `excuse`, `mission`, `correction`. | 
**leave_half** | Option<**String**> | `first` | `second`: which half of the day a half-day leave takes off. Omitted on a half day = the first. | [optional]
**leave_type_id** | Option<**uuid::Uuid**> | Deprecated (RQ-2): ignored. Leave has no types. | [optional]
**location** | Option<**String**> |  | [optional]
**on_date** | **chrono::NaiveDate** |  | 
**reason** | Option<**String**> |  | [optional]
**title** | Option<**String**> | A mission's title; when omitted the note is used. | [optional]
**to_time** | Option<**String**> | Branch-local wall clock. An excuse ending at or before it starts runs past midnight. | [optional]
**work_shift_id** | Option<**uuid::Uuid**> | The shift a late arrival, early departure or excuse is for. Omitted = the shift of the day its time falls in. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


