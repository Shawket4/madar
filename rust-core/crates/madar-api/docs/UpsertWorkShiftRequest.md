# UpsertWorkShiftRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**break_minutes** | Option<**i32**> |  | [optional]
**checkin_window_minutes** | Option<**i32**> |  | [optional]
**day_times** | Option<[**Vec<models::DayTime>**](DayTime.md)> | Its own times on some weekdays (each must be a valid day). Omit to keep them; an empty list clears them. | [optional]
**end_time** | **String** |  | 
**grace_minutes** | Option<**i32**> |  | [optional]
**half_day_threshold_minutes** | Option<**i32**> |  | [optional]
**is_active** | Option<**bool**> |  | [optional]
**name** | **String** |  | 
**ot_day_multiplier** | Option<**f64**> | The block's own day-overtime rate (RU-8). Omit to keep it, null to go back to the branch's rules. | [optional]
**ot_night_multiplier** | Option<**f64**> | The block's own night-overtime rate. Omit to keep, null to clear. | [optional]
**overtime_multiplier** | Option<**f64**> |  | [optional]
**overtime_threshold_minutes** | Option<**i32**> |  | [optional]
**paid_break** | Option<**bool**> |  | [optional]
**start_time** | **String** |  | 
**valid_days** | Option<**Vec<i32>**> | Weekdays it may be rostered on (0 = Sunday … 6 = Saturday). Omit to keep them (all days for a new block). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


