# RepricingSuggestion

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**below_cost** | **bool** | True when the item currently sells BELOW cost (negative margin). | 
**cost** | **i64** | Complete recipe cost, piastres. | 
**current_price** | **i64** | Current selling price, piastres. | 
**item_name** | **String** |  | 
**margin_pct** | **f64** | `(price − cost) / price`, current. | 
**menu_item_id** | **uuid::Uuid** |  | 
**size_label** | **String** | `\"one_size\"` for items without sizes. | 
**suggested_price** | **i64** | Target-restoring price `ceil(cost / (1 − target))` to whole EGP, piastres. | 
**target_pct** | **f64** | The org/branch target margin this suggestion aims for. | 
**uplift** | **i64** | `suggested_price − current_price`, piastres. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


