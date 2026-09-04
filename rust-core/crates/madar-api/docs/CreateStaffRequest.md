# CreateStaffRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**attendance_record_id** | Option<**uuid::Uuid**> | `correction` only — the record whose punch is wrong. | [optional]
**end_date** | Option<**chrono::NaiveDate**> |  | [optional]
**from_time** | Option<**String**> |  | [optional]
**is_half_day** | Option<**bool**> |  | [optional]
**kind** | **String** | One of `leave`, `late_arrival`, `early_departure`, `excuse`, `mission`, `correction`. | 
**leave_type_id** | Option<**uuid::Uuid**> |  | [optional]
**location** | Option<**String**> |  | [optional]
**on_date** | **chrono::NaiveDate** |  | 
**reason** | Option<**String**> |  | [optional]
**title** | Option<**String**> |  | [optional]
**to_time** | Option<**String**> |  | [optional]
**user_id** | Option<**uuid::Uuid**> | Admin-only. Omitted on `/staff/me/_*`, where it is always the caller. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


