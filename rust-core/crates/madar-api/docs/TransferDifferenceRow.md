# TransferDifferenceRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**destination_branch_name** | **String** |  | 
**difference** | **f64** | received − sent; negative = transit loss. | 
**ingredient_name** | **String** |  | 
**note** | Option<**String**> |  | [optional]
**org_ingredient_id** | **uuid::Uuid** |  | 
**qty_received** | **f64** |  | 
**qty_sent** | **f64** |  | 
**received_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**reference** | **String** |  | 
**source_branch_name** | **String** |  | 
**transfer_id** | **uuid::Uuid** |  | 
**unit** | **String** |  | 
**unit_cost** | Option<**f64**> |  | [optional]
**value_difference** | Option<**i64**> | `difference × unit_cost`, piastres; `None` when the cost is unknown. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


