# Bundle

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**available_from_date** | Option<**chrono::NaiveDate**> |  | [optional]
**available_from_time** | Option<**String**> |  | [optional]
**available_until_date** | Option<**chrono::NaiveDate**> |  | [optional]
**available_until_time** | Option<**String**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**description** | Option<**String**> |  | [optional]
**description_translations** | Option<**serde_json::Value**> |  | 
**id** | **uuid::Uuid** |  | 
**image_url** | Option<**String**> |  | [optional]
**name** | **String** |  | 
**name_translations** | Option<**serde_json::Value**> |  | 
**org_id** | **uuid::Uuid** |  | 
**price** | **i32** |  | 
**status** | [**models::BundleStatus**](BundleStatus.md) |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


