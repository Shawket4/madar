# AttendanceRecord

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**business_date** | **chrono::NaiveDate** |  | 
**check_in_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**check_in_distance_meters** | Option<**f64**> |  | [optional]
**check_in_latitude** | Option<**f64**> |  | [optional]
**check_in_longitude** | Option<**f64**> |  | [optional]
**check_in_method** | Option<**String**> |  | [optional]
**check_out_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**check_out_distance_meters** | Option<**f64**> |  | [optional]
**check_out_latitude** | Option<**f64**> |  | [optional]
**check_out_longitude** | Option<**f64**> |  | [optional]
**check_out_method** | Option<**String**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**early_leave_minutes** | **i32** |  | 
**edit_reason** | Option<**String**> |  | [optional]
**edited_by** | Option<**uuid::Uuid**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**is_manual** | **bool** |  | 
**late_minutes** | **i32** |  | 
**notes** | Option<**String**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**overtime_minutes** | **i32** |  | 
**scheduled_end_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**scheduled_start_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**status** | **String** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**user_id** | **uuid::Uuid** |  | 
**user_name** | Option<**String**> |  | [optional]
**work_shift_id** | Option<**uuid::Uuid**> |  | [optional]
**work_shift_name** | Option<**String**> |  | [optional]
**worked_minutes** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


