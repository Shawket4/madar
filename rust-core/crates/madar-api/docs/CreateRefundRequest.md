# CreateRefundRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount** | **i32** | Minor units, > 0. Together with every refund already on the order it may not exceed `orders.total_amount`. | 
**client_ref** | Option<**uuid::Uuid**> | Client-minted idempotency key. A retried request or a replayed offline queue carrying the same key gets the original refund back instead of handing the money out again. | [optional]
**issued_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the refund was issued. Omit for live requests — the server stamps `now()`. An offline till sends the real time; future values are rejected. | [optional]
**lines** | Option<[**Vec<models::RefundLineInput>**](RefundLineInput.md)> |  | [optional]
**method** | **String** | How the money went back — a name from the org's payment-method vocabulary. One tender per refund; a split is two refunds. | 
**note** | Option<**String**> | Free-text explanation. Required when `reason` is `other`. | [optional]
**order_id** | **uuid::Uuid** | The settled sale the money goes back against. | 
**reason** | [**models::RefundReason**](RefundReason.md) |  | 
**shift_id** | Option<**uuid::Uuid**> | The shift whose drawer the money leaves. Omit for a live request and the actor's own open shift at the order's branch is used; a replayed offline refund must name the shift it was issued in, the way a queued sale does. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


