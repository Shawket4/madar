# OrderDeal

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**deal_rule_id** | **uuid::Uuid** |  | 
**discount** | **i32** | What came off the lines (the till's figure on a replay). | 
**discount_server** | Option<**i32**> | The server's verdict; equals `discount` live; `null` when not computable. | [optional]
**id** | **uuid::Uuid** |  | 
**lines** | [**Vec<models::OrderDealLine>**](OrderDealLine.md) |  | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**times** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


