# DealWrite

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**get_percent** | Option<**i32**> | buy_get only (1–100; 100 = free). | [optional]
**get_qty** | Option<**i32**> | buy_get only (1–20). | [optional]
**is_active** | Option<**bool**> |  | [optional]
**kind** | **String** | `n_for_price` | `buy_get`. | 
**max_per_order** | Option<**i32**> |  | [optional]
**name** | **String** |  | 
**name_translations** | Option<**serde_json::Value**> |  | [optional]
**pool** | [**Vec<models::DealPoolEntry>**](DealPoolEntry.md) |  | 
**price** | Option<**i32**> | n_for_price only. | [optional]
**qty** | **i32** | N (n_for_price, 2–20) or the \"buy\" count (buy_get, 1–20). | 
**reward_pool** | Option<[**Vec<models::DealPoolEntry>**](DealPoolEntry.md)> |  | [optional]
**sort** | Option<**i32**> |  | [optional]
**windows** | Option<[**Vec<models::SaleWindow>**](SaleWindow.md)> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


