# DeliveryMenuDiscount

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**dtype** | **String** | \"percentage\" | \"fixed\". | 
**id** | **uuid::Uuid** |  | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**value** | **i64** | LEGACY SPELLING — an integer, 0-100 for a percentage; piastres for `fixed`. See `discounts::wire`. | 
**value_rate** | **f64** | The stored fraction, for clients that know to ask. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


