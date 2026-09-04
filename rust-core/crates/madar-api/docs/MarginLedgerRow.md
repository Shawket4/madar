# MarginLedgerRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**category_name** | Option<**String**> |  | [optional]
**class** | Option<**String**> | Classic menu-engineering class (Kasavana–Smith): `star` | `workhorse` | `challenge` | `dog`. High/low popularity splits at the 70%-rule threshold (0.70/n of tracked units); high/low profit splits at the weighted-average unit contribution margin. `null` for rows that can't be classified (no sales in the period, or cost unknown). | [optional]
**cost** | Option<**i64**> | Piastres under the chosen basis; `null` = unknown (never 0). | [optional]
**flags** | [**Vec<models::Signal>**](Signal.md) |  | 
**item_name** | **String** |  | 
**margin** | Option<**i64**> |  | [optional]
**margin_pct** | Option<**f64**> |  | [optional]
**margin_share_pct** | Option<**f64**> | This row's share of the total KNOWN margin (null when margin unknown or total margin ≤ 0). | [optional]
**menu_item_id** | **uuid::Uuid** |  | 
**on_menu** | **bool** | False when this SKU no longer exists on the active menu (historical sales under a removed size/item). | 
**popularity_pct** | Option<**f64**> | This SKU's share of tracked units (the popularity axis), when classified. | [optional]
**prev_margin** | Option<**i64**> |  | [optional]
**prev_quantity** | **i64** | Previous equal-length period, for the trend column. | 
**quantity_sold** | **i64** |  | 
**revenue** | **i64** |  | 
**size_label** | **String** | `\"one_size\"` for items without sizes. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


