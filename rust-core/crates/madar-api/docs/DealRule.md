# DealRule

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_overrides** | [**Vec<models::DealBranchOverride>**](DealBranchOverride.md) |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**get_percent** | Option<**i32**> |  | [optional]
**get_qty** | Option<**i32**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**kind** | **String** | `n_for_price` | `buy_get`. | 
**max_per_order** | Option<**i32**> |  | [optional]
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**pool** | [**Vec<models::DealPoolEntry>**](DealPoolEntry.md) |  | 
**price** | Option<**i32**> | n_for_price: the price of `qty` units, piastres. | [optional]
**qty** | **i32** |  | 
**reward_pool** | [**Vec<models::DealPoolEntry>**](DealPoolEntry.md) | buy_get only; `[]` = the rewarded units come from `pool`. | 
**sell** | Option<[**models::ChannelToggles**](ChannelToggles.md)> | Feed rows only: the branch's channel toggles (§11.1). Absent elsewhere. | [optional]
**sort** | **i32** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**windows** | [**Vec<models::SaleWindow>**](SaleWindow.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


