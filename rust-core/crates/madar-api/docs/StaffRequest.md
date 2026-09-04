# StaffRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**attendance_record_id** | Option<**uuid::Uuid**> | The record a `correction` proposes to fix. `None` for every other kind. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**decided_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**decided_by** | Option<**uuid::Uuid**> |  | [optional]
**decision_note** | Option<**String**> |  | [optional]
**end_date** | Option<**chrono::NaiveDate**> | Set for `leave` and `mission`; the span's last day. | [optional]
**from_time** | Option<**String**> | Start of the excused window. `None` = open to the shift's start. | [optional]
**id** | **uuid::Uuid** |  | 
**is_half_day** | **bool** |  | 
**is_paid** | Option<**bool**> | Whether the excused time is paid. `None` until decided. | [optional]
**kind** | **String** | `leave` | `late_arrival` | `early_departure` | `excuse` | `mission`. | 
**leave_type_id** | Option<**uuid::Uuid**> |  | [optional]
**leave_type_name** | Option<**String**> |  | [optional]
**location** | Option<**String**> |  | [optional]
**on_date** | **chrono::NaiveDate** |  | 
**org_id** | **uuid::Uuid** |  | 
**reason** | Option<**String**> |  | [optional]
**status** | **String** |  | 
**title** | Option<**String**> |  | [optional]
**to_time** | Option<**String**> | End of the excused window. `None` = open to the shift's end. | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**user_id** | **uuid::Uuid** |  | 
**user_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


