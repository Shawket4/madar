# Adjustment

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_piastres** | Option<**i64**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**effective_date** | **chrono::NaiveDate** |  | 
**employee_id** | **uuid::Uuid** |  | 
**employee_name** | **String** |  | 
**ends_on** | Option<**chrono::NaiveDate**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**kind** | **String** | `bonus` · `deduction` | 
**percent_of_base** | Option<**f64**> |  | [optional]
**reason** | **String** |  | 
**recurring** | **bool** |  | 
**source** | **String** |  | 
**status** | **String** | `pending` (waits for the owner) · `approved` · `rejected` | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


