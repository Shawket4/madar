# StockMovement

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**approved_by_name** | Option<**String**> | The manager who approved it on the till. | [optional]
**balance_after** | **f64** |  | 
**below_zero** | **bool** |  | 
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | Option<**String**> | Branch name; only populated by the all-branches waste roll-up (nil {branch_id}). `None` for single-branch queries that do not select it. | [optional]
**branch_stock_id** | Option<**uuid::Uuid**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**created_by_name** | Option<**String**> |  | [optional]
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**device_name** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**movement_type** | **String** | inventory_movement_type: sale | void_restock | adjustment_add | adjustment_remove | waste | transfer_out | transfer_in | purchase_in | purchase_return | stock_count | 
**note** | Option<**String**> |  | [optional]
**occurred_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When it happened on the device (a queued waste lands later). | [optional]
**org_ingredient_id** | **uuid::Uuid** |  | 
**quantity** | **f64** | Signed delta applied to stock (consumption negative, replenishment positive). | 
**reason** | Option<**String**> |  | [optional]
**source_id** | Option<**uuid::Uuid**> |  | [optional]
**source_type** | Option<**String**> |  | [optional]
**till_id** | Option<**uuid::Uuid**> |  | [optional]
**unit** | **String** |  | 
**unit_cost** | Option<**i64**> | Piastres per unit at movement time; `null` ⟺ unknown. | [optional]
**waste_quantity** | Option<**f64**> | The quantity as the person typed it, in `waste_unit`. | [optional]
**waste_size_label** | Option<**String**> |  | [optional]
**waste_source** | Option<**String**> | `pos` | `dashboard` | `order` (a voided made order). | [optional]
**waste_subject_kind** | Option<**String**> | `ingredient` | `menu_item`, when the waste was recorded with a header. | [optional]
**waste_subject_name** | Option<**String**> | What the person picked (the menu item for an exploded item waste). | [optional]
**waste_unit** | Option<**String**> |  | [optional]
**waste_value_minor** | Option<**i64**> | The whole waste's value (all its lines), piastres. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


