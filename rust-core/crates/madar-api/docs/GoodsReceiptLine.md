# GoodsReceiptLine

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**line_cost** | Option<**i64**> | Piastres this delivery cost (negative for a return); null when unknown. | [optional]
**org_ingredient_id** | **uuid::Uuid** |  | 
**purchase_order_line_id** | Option<**uuid::Uuid**> |  | [optional]
**quantity** | **f64** | Base stock units received (+) or returned (−). | 
**unit_cost** | Option<**i64**> | Piastres per base stock unit (actual), rounded to whole piastres. | [optional]
**unit_cost_exact** | Option<**f64**> | Piastres per base stock unit at full precision. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


