# ComboEconomicsRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**description** | Option<**String**> |  | [optional]
**description_translations** | Option<**serde_json::Value**> |  | [optional]
**is_active** | Option<**bool**> |  | [optional]
**name** | **String** |  | 
**name_translations** | Option<**serde_json::Value**> |  | [optional]
**price** | **i32** | P, piastres: the combo's `one_size` price (its `base_price`). | 
**slots** | [**Vec<models::ComboSlotWrite>**](ComboSlotWrite.md) |  | 
**windows** | Option<[**Vec<models::SaleWindow>**](SaleWindow.md)> |  | [optional]
**branch_id** | Option<**uuid::Uuid**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


