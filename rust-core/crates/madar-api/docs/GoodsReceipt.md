# GoodsReceipt

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**id** | **uuid::Uuid** |  | 
**is_return** | **bool** | true ⟹ a return to supplier (negative stock effect). | 
**lines** | [**Vec<models::GoodsReceiptLine>**](GoodsReceiptLine.md) |  | 
**note** | Option<**String**> |  | [optional]
**purchase_order_id** | Option<**uuid::Uuid**> |  | [optional]
**received_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**received_by** | **uuid::Uuid** |  | 
**received_by_name** | Option<**String**> |  | [optional]
**reference** | Option<**String**> |  | [optional]
**supplier_id** | Option<**uuid::Uuid**> |  | [optional]
**supplier_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


