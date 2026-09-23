# WorkShiftBrief

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**crosses_midnight** | **bool** |  | 
**day_times** | [**Vec<models::DayTime>**](DayTime.md) | Its own times on some weekdays; show that day's times. | 
**end_time** | **String** |  | 
**grace_minutes** | **i32** |  | 
**id** | **uuid::Uuid** |  | 
**name** | **String** |  | 
**start_time** | **String** |  | 
**valid_days** | **Vec<i32>** | Weekdays it may be rostered on (0 = Sunday … 6 = Saturday): offer it only on those. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


