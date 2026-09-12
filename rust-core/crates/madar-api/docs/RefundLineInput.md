# RefundLineInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount** | **i32** | The share of the refund's amount attributed to this line, minor units. Zero is allowed (a reward line sent back for nothing). The lines of a refund may not add up to more than the refund. | 
**order_item_id** | **uuid::Uuid** |  | 
**quantity** | **i32** | How many of the line's units this refund is for. Held, cumulatively across every refund of the order, to what the line sold. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


