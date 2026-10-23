# ItemSales

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**avg_extra** | Option<**i64**> | Piastres per unit sold: `extras_total / quantity_sold`, rounded to the piastre (half away from zero). Additive. | [optional]
**extras_total** | Option<**i64**> | Piastres charged on top of those size prices, before any discount: every add-on and swap on the lines (their charge, a staff comp added back) plus optional fields × quantity. `paid − menu price of the size`, summed; never below zero (see `order_line_extras` in migrations/20261023100000_rollup_item_extras.sql). Additive. | [optional]
**item_name** | **String** |  | 
**item_name_translations** | **serde_json::Value** |  | 
**menu_item_id** | **uuid::Uuid** |  | 
**menu_total** | Option<**i64**> | Piastres: the menu price of the size each unit was sold in, AT SALE TIME, summed (`order_items.unit_price × quantity`; no add-ons, swaps, optional fields, discounts or rewards). Additive (2026-10-18): absent from older servers. | [optional]
**quantity_sold** | **i64** |  | 
**revenue** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


