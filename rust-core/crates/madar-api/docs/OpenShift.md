# OpenShift

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**claimed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the live claim was made; null while open. | [optional]
**claimed_by** | Option<**uuid::Uuid**> | The employee who claimed it. | [optional]
**claimed_by_name** | Option<**String**> |  | [optional]
**end_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**on_date** | **chrono::NaiveDate** |  | 
**shift_name** | **String** |  | 
**start_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**status** | **String** | `open` · `claimed` · `filled` · `cancelled` | 
**work_shift_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


