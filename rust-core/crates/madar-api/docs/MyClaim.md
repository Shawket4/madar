# MyClaim

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**claimed_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**decided_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When it was decided or withdrawn; null while pending, and on a claim decided before the server kept this history. | [optional]
**id** | **uuid::Uuid** |  | 
**on_date** | **chrono::NaiveDate** |  | 
**open_shift_id** | **uuid::Uuid** |  | 
**shift_name** | **String** |  | 
**status** | **String** | `pending` · `approved` · `declined` · `withdrawn`. A shift the manager took back while the claim waited is `declined`. | 
**work_shift_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


