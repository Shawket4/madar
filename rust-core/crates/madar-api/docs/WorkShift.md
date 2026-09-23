# WorkShift

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | `None` = an org-wide template usable at any branch. | [optional]
**break_minutes** | **i32** |  | 
**checkin_window_minutes** | **i32** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**crosses_midnight** | **bool** | Derived by the database from `end_time <= start_time`. | 
**day_times** | Option<[**Vec<models::DayTime>**](DayTime.md)> | Its own times on some weekdays; other valid days use the default. | [optional]
**end_time** | **String** |  | 
**grace_minutes** | **i32** |  | 
**half_day_threshold_minutes** | Option<**i32**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**ot_day_multiplier** | Option<**f64**> | This block's own day-overtime rate; `None` = the branch's rules (RU-8). | [optional]
**ot_night_multiplier** | Option<**f64**> | This block's own night-overtime rate; `None` = the branch's rules. | [optional]
**over_presence_cap** | Option<**bool**> | Some version of it (default or a weekday's) is longer than the labour presence cap. A warning, never a block (RU-13). | [optional]
**overtime_multiplier** | **f64** |  | 
**overtime_threshold_minutes** | **i32** |  | 
**paid_break** | **bool** |  | 
**start_time** | **String** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**valid_days** | **Vec<i32>** | The weekdays the block may be rostered on (0 = Sunday … 6 = Saturday). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


