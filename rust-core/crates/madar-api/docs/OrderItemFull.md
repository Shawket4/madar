# OrderItemFull

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**bundle_id** | Option<**uuid::Uuid**> |  | [optional]
**bundle_unit_price** | Option<**i32**> |  | [optional]
**cost_missing** | **bool** | True when any cost component could not be resolved. | 
**deductions_snapshot** | Option<**serde_json::Value**> |  | 
**id** | **uuid::Uuid** |  | 
**is_reward** | Option<**bool**> | A loyalty reward paid for some or all of this line. The receipt and the kitchen say \"Reward\" beside it. | [optional]
**item_name** | **String** |  | 
**line_cost** | Option<**i64**> | Full line COGS in piastres (recipe + addons + optionals + components). `null` ⟺ unknown. | [optional]
**line_total** | **i32** |  | 
**menu_item_id** | Option<**uuid::Uuid**> |  | [optional]
**name_translations** | **serde_json::Value** |  | 
**notes** | Option<**String**> |  | [optional]
**order_id** | **uuid::Uuid** |  | 
**quantity** | **i32** |  | 
**reward_covered** | Option<**i32**> | Minor units the reward took off this line (0 for a paid line). | [optional]
**reward_units** | Option<**i32**> | How many of `quantity` the reward covered. | [optional]
**size_label** | Option<**String**> |  | [optional]
**staff_comp_minor** | Option<**i32**> | A staff drink: what the branch's pool comped on this line, in minor units, size part and required-choice part together. ALREADY taken off `line_total` (the size part) and the add-ons' `line_total` (their part): print it as a line discount, never subtract it again. 0 on a paid line. | [optional]
**staff_drink_id** | Option<**uuid::Uuid**> | The `staff_drinks` row this line is (`GET /staff-pool/drinks`). | [optional]
**unit_cost** | Option<**i64**> | Recipe-only cost per unit in piastres (incl. swaps). `null` ⟺ unknown or bundle line. | [optional]
**unit_price** | **i32** |  | 
**addons** | [**Vec<models::OrderItemAddon>**](OrderItemAddon.md) |  | 
**bundle_components** | Option<[**Vec<models::OrderBundleComponentFull>**](OrderBundleComponentFull.md)> |  | [optional]
**optionals** | [**Vec<models::OrderItemOptional>**](OrderItemOptional.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


