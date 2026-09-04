# MyAttendanceToday

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**blocked_reason** | Option<**String**> | Why `can_check_in` is false, in words the app can show verbatim. | [optional]
**branch_id** | Option<**uuid::Uuid**> | WHERE to clock in today. Resolved server-side — from the open record, the rostered shift's branch, or the employee's single branch assignment — so the app never has to ask. A branch picker would make the geofence answerable to a dropdown, which defeats the point of having one. `None` means we cannot tell, and the app should say so rather than guess. | [optional]
**branch_name** | Option<**String**> | That branch's name, so the app's geofence chip can say WHERE it is about to clock in rather than merely that it can. | [optional]
**business_date** | **chrono::NaiveDate** | The business date in the relevant branch's timezone — not the device's. | 
**can_check_in** | **bool** |  | 
**can_check_out** | **bool** |  | 
**closed_records** | [**Vec<models::AttendanceRecord>**](AttendanceRecord.md) | Records already closed today. | 
**open_record** | Option<[**models::AttendanceRecord**](AttendanceRecord.md)> | The still-open record, when the employee is currently clocked in. | [optional]
**scheduled** | [**Vec<models::ResolvedShift>**](ResolvedShift.md) | Shifts rostered for today. Empty = a rest day. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


