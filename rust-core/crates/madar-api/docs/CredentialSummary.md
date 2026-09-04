# CredentialSummary

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**last_used_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Last successful authentication, or null if the partner has never pulled. | [optional]
**name** | **String** |  | 
**revoked_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**username** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


