# Suggestion

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**by_default** | **bool** | The gender default decided it: without it someone else would have been suggested (it says so). | 
**confidence** | **i32** | 0–100. Low (≤ 40) whenever the gender default decided it. | 
**date** | **chrono::NaiveDate** |  | 
**employee_id** | **uuid::Uuid** | Who the suggestion puts on the shift. | 
**employee_name** | **String** |  | 
**end_time** | Option<**String**> |  | [optional]
**from_employee_id** | Option<**uuid::Uuid**> | Who it takes off it, for a reassignment. | [optional]
**from_employee_name** | Option<**String**> |  | [optional]
**id** | **String** | Opaque; send it back to accept or reject. | 
**reason_args** | Option<**serde_json::Value**> |  | 
**reason_key** | **String** | A core i18n key for the one-line reason, and its arguments. | 
**shift_name** | **String** |  | 
**start_time** | Option<**String**> | The shift's times that day (a day-scoped block's own, else its default). | [optional]
**work_shift_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


