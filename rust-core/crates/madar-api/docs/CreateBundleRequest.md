# CreateBundleRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**available_from_date** | Option<**chrono::NaiveDate**> |  | [optional]
**available_from_time** | Option<**String**> |  | [optional]
**available_until_date** | Option<**chrono::NaiveDate**> |  | [optional]
**available_until_time** | Option<**String**> |  | [optional]
**branch_ids** | Option<**Vec<uuid::Uuid>**> |  | [optional]
**components** | [**Vec<models::CreateBundleComponentInput>**](CreateBundleComponentInput.md) |  | 
**description** | Option<**String**> |  | [optional]
**description_translations** | Option<**serde_json::Value**> |  | [optional]
**image_url** | Option<**String**> |  | [optional]
**name** | **String** |  | 
**name_translations** | Option<**serde_json::Value**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**price** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


