# PutOverrideRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** |  | 
**end_time** | Option<**String**> |  | [optional]
**on_date** | **chrono::NaiveDate** |  | 
**reason** | Option<**String**> |  | [optional]
**start_time** | Option<**String**> | This assignment's own from/to (both or neither). | [optional]
**work_shift_id** | Option<**uuid::Uuid**> | Omit (or send null) to mark the date an explicit day off. Otherwise the whole date becomes this one shift; `PUT /staff/schedules/days` sets a split day. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


