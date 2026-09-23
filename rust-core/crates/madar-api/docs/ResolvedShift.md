# ResolvedShift

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | The branch it is worked at (the block's, else the person's first). | [optional]
**break_minutes** | **i32** |  | 
**checkin_window_minutes** | **i32** |  | 
**crosses_midnight** | **bool** | Ends on the following date. | 
**employee_id** | **uuid::Uuid** | Whose assignment this is. | 
**end_time** | **String** |  | 
**from_override** | **bool** | The date holds its own set (a date change), not the pattern. | 
**grace_minutes** | **i32** |  | 
**half_day_threshold_minutes** | Option<**i32**> |  | [optional]
**name** | **String** |  | 
**on_date** | **chrono::NaiveDate** | The business date: the day the shift starts on (SC-10). | 
**overtime_multiplier** | **f64** |  | 
**overtime_threshold_minutes** | **i32** |  | 
**paid_break** | **bool** |  | 
**scheduled_end_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**scheduled_start_at** | **chrono::DateTime<chrono::FixedOffset>** | The EFFECTIVE window: the assignment's own times, else the block's time for that weekday, else its default. | 
**start_time** | **String** | Effective wall-clock times in the branch's zone. | 
**times_edited** | **bool** | This assignment has its own from/to (shown as edited). | 
**work_shift_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


