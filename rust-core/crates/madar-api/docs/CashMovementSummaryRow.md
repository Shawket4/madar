# CashMovementSummaryRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount** | **i32** |  | 
**corrects_id** | Option<**uuid::Uuid**> |  | [optional]
**corrects_kind** | Option<**String**> | The kind of the movement `corrects_id` points at, so a printed report can say \"correction of pay-out\" and the totals can net the pair inside the bucket the mistake was made in. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**kind** | **String** |  | 
**moved_by_name** | **String** |  | 
**note** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


