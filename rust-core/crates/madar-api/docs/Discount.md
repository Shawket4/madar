# Discount

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**dtype** | **String** |  | 
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**org_id** | **uuid::Uuid** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**value** | **f64** | Polymorphic by `dtype`: a FRACTION for `percentage` (0.14 = 14%, like every other rate in this schema), or minor units for `fixed`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


