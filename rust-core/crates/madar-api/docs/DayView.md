# DayView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** |  | 
**follows_pattern** | **bool** | The date follows the standing pattern (no date change). | 
**on_date** | **chrono::NaiveDate** |  | 
**shifts** | [**Vec<models::ResolvedShift>**](ResolvedShift.md) | Empty = a day off (or nothing rostered). | 
**warnings** | [**Vec<models::LabourWarning>**](LabourWarning.md) | Labour limits the person's week now goes past. Warnings, never blocks. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


