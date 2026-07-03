# MenuItemWithCosts

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**base_price** | **i32** |  | 
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**default_milk_addon_id** | Option<**String**> |  | [optional]
**deleted_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**description** | Option<**String**> |  | [optional]
**description_translations** | **serde_json::Value** |  | 
**id** | **uuid::Uuid** |  | 
**image_url** | Option<**String**> |  | [optional]
**is_active** | **bool** |  | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**org_id** | **uuid::Uuid** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**sku_costs** | [**Vec<models::SkuCost>**](SkuCost.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


