# TableOrderRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**customer_name** | Option<**String**> | Who is at the table, if they offered a name. Shown on the bill so the waiter can find them. | [optional]
**customer_phone** | Option<**String**> | Their phone, if they offered one. Optional and never required: with a valid number (and a name) the bill is linked to that customer — created on first contact, `source = table_qr` — so the visit counts toward them. A number that is not valid is ignored; the order is never refused. | [optional]
**idempotency_key** | Option<**uuid::Uuid**> | Client-minted, so a phone that resends on a flaky connection does not order twice. This is the ONLY protection against a double-send, because a customer's browser has no outbox to dedup against. | [optional]
**items** | [**Vec<models::OrderItemInput>**](OrderItemInput.md) | What they want. Named, never priced — see the module docs. | 
**table_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


