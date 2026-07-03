# CreateOpenTicketRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**customer_name** | Option<**String**> |  | [optional]
**discount_id** | Option<**uuid::Uuid**> | Optional discount the waiter applied at order time (overridable at settle). | [optional]
**discount_type** | Option<**String**> |  | [optional]
**discount_value** | Option<**i32**> |  | [optional]
**guest_count** | Option<**i32**> |  | [optional]
**idempotency_key** | Option<**uuid::Uuid**> | Client-minted dedup key for the ticket (exactly-once across LAN + cloud). | [optional]
**items** | [**Vec<models::OrderItemInput>**](OrderItemInput.md) | Client-priced items (same shape as a POS order line) — recorded verbatim. | 
**notes** | Option<**String**> |  | [optional]
**round_idempotency_key** | Option<**uuid::Uuid**> | Per-round dedup key for the first round. | [optional]
**table_id** | Option<**uuid::Uuid**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


