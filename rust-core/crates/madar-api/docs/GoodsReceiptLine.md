# GoodsReceiptLine

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**purchase_order_line_id** | Option<**uuid::Uuid**> |  | [optional]
**quantity** | **f64** | Base stock units received (+) or returned (−). | 
**unit_cost** | Option<**i64**> | Piastres per base stock unit (actual). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


