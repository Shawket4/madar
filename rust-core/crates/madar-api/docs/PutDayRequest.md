# PutDayRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** |  | 
**on_date** | **chrono::NaiveDate** |  | 
**reason** | Option<**String**> |  | [optional]
**shifts** | [**Vec<models::DayBlock>**](DayBlock.md) | Every shift the person works that date; empty = a day off. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


