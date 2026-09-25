# Combo

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**available_now** | **bool** | Sellable right now on the till at the requested branch (or anywhere, org-level): active, the POS channel on, a window open, every required slot with an available choice. | 
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**description** | Option<**String**> |  | [optional]
**description_translations** | **serde_json::Value** |  | 
**economics** | [**models::ComboEconomics**](ComboEconomics.md) |  | 
**id** | **uuid::Uuid** |  | 
**image_url** | Option<**String**> |  | [optional]
**is_active** | **bool** |  | 
**is_fixed** | **bool** | C1's fixed bundle: every slot has exactly one item choice with min == max. | 
**kind** | **String** | Always `combo`. | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**price** | **i32** | P, piastres (the catalogue price; branch prices live in `/menu/pricing`). | 
**slots** | [**Vec<models::ComboSlot>**](ComboSlot.md) |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**windows** | [**Vec<models::SaleWindow>**](SaleWindow.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


