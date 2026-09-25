# AttendanceFlag

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**attendance_record_id** | Option<**uuid::Uuid**> |  | [optional]
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**deduction_id** | Option<**uuid::Uuid**> | The deduction the flag was handled with (a deduct or an unpaid excuse), and its status: `approved`, or `pending` = over the manager's limit, it waits for the owner (minor default M33). | [optional]
**deduction_status** | Option<**String**> |  | [optional]
**detected_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**employee_id** | **uuid::Uuid** |  | 
**employee_name** | **String** |  | 
**id** | **uuid::Uuid** |  | 
**kind** | **String** | `left_mid_shift` · `suspicious` · `tracking_off` · `time_unverified` · `new_phone` · `cover` | 
**minutes_away** | **i32** |  | 
**resolution** | Option<**String**> |  | [optional]
**resolved_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**suggested_deduction_piastres** | **i64** | Time away × the person's minute rate, rounded to the nearest 5 EGP (CL-7). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


