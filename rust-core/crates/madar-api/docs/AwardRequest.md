# AwardRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**customer_id** | Option<**uuid::Uuid**> |  | [optional]
**order_id** | Option<**uuid::Uuid**> | The server's order id — the history path, where the order is synced. | [optional]
**order_key** | Option<**uuid::Uuid**> | The client-minted idempotency key — the just-checked-out path, where the order may not have reached the server yet. Resolved to the same order. | [optional]
**phone** | Option<**String**> |  | [optional]
**requested_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the teller pressed the button. Absent = now.  An offline till stamps the press and queues it, so a drain days later still credits an award that was made in time. Bounded on arrival (see the module docs) so it cannot be used to reach outside the window. | [optional]
**token** | Option<**String**> | Who. A scanned pass token, a typed phone, or an already-resolved member. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


