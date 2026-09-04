# WorkShift

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | `None` = an org-wide template usable at any branch. | [optional]
**break_minutes** | **i32** |  | 
**checkin_window_minutes** | **i32** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**crosses_midnight** | **bool** | Derived by the database from `end_time <= start_time`. | 
**end_time** | **String** |  | 
**grace_minutes** | **i32** |  | 
**half_day_threshold_minutes** | Option<**i32**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**overtime_multiplier** | **f64** |  | 
**overtime_threshold_minutes** | **i32** |  | 
**paid_break** | **bool** |  | 
**start_time** | **String** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


