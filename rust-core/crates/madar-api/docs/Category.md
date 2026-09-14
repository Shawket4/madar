# Category

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**deleted_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**image** | Option<[**models::AssetGroupRef**](AssetGroupRef.md)> | Asset refs (Track B4, §11.10); null when no asset or not attached by this endpoint. | [optional]
**image_url** | Option<**String**> |  | [optional]
**is_active** | **bool** |  | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**org_id** | **uuid::Uuid** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


