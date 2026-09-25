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
**check_out_reason** | Option<**String**> | Why someone else punched this person OUT; the in-reason stays in `punch_reason` (AT-10, Mac E2E BC-1). | [optional]
**cover_status** | Option<**String**> | `pending` · `confirmed` · `rejected` for a cover. | [optional]
**covered_employee_id** | Option<**uuid::Uuid**> | A cover: whose shift this person worked (CV-*). | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**early_leave_minutes** | **i32** |  | 
**edit_reason** | Option<**String**> |  | [optional]
**edited_by** | Option<**uuid::Uuid**> |  | [optional]
**employee_id** | **uuid::Uuid** |  | 
**employee_name** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**is_manual** | **bool** |  | 
**late_minutes** | **i32** |  | 
**month_closed** | Option<**bool**> | Its day is in an approved or paid month (period_lock): an overtime or cover approval, a correction or a deduction on it is refused with PERIOD_CLOSED, so clients don't offer them. | [optional]
**notes** | Option<**String**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**overtime_minutes** | **i32** |  | 
**overtime_status** | Option<**String**> | `pending` · `approved` · `rejected` when overtime needs a decision. | [optional]
**punch_reason** | Option<**String**> | Why someone else punched this person IN (or the only punch they made). | [optional]
**scheduled_end_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**scheduled_start_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**status** | **String** |  | 
**status_overridden** | Option<**bool**> | A manager set this day's status by hand; automation keeps it (AT-7). | [optional]
**tracking_off** | **bool** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**work_shift_id** | Option<**uuid::Uuid**> |  | [optional]
**work_shift_name** | Option<**String**> |  | [optional]
**worked_minutes** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


