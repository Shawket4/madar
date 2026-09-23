# Suggestion

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**by_default** | **bool** | The gender default decided it (it says so). | 
**confidence** | **i32** | 0–100. | 
**date** | **chrono::NaiveDate** |  | 
**employee_id** | **uuid::Uuid** | Who the suggestion puts on the shift. | 
**employee_name** | **String** |  | 
**from_employee_id** | Option<**uuid::Uuid**> | Who it takes off it, for a reassignment. | [optional]
**from_employee_name** | Option<**String**> |  | [optional]
**id** | **String** | Opaque; send it back to accept or reject. | 
**reason_args** | Option<**serde_json::Value**> |  | 
**reason_key** | **String** | A core i18n key for the one-line reason, and its arguments. | 
**shift_name** | **String** |  | 
**work_shift_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


