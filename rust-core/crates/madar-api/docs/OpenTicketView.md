# OpenTicketView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**bill** | Option<[**models::TicketBill**](TicketBill.md)> | The bill as the SERVER prices it — see [`TicketBill`]. This is the figure the till shows and the drawer collects, because it is the figure the settle will book; `subtotal` above is only its first line. | [optional]
**booking_id** | Option<**uuid::Uuid**> | The booking this ticket seated, if the party had one. | [optional]
**branch_id** | **uuid::Uuid** |  | 
**customer_name** | Option<**String**> |  | [optional]
**discount_id** | Option<**uuid::Uuid**> | The discount the waiter put on the bill at fire time, if any. Shown so the cashier can SEE what a settle will inherit — and clear it with an explicit `discount_type: \"none\"` rather than have it applied silently. | [optional]
**discount_type** | Option<**String**> |  | [optional]
**discount_value** | Option<**f64**> |  | [optional]
**guest_count** | Option<**i32**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**items** | [**Vec<models::OpenTicketItemView>**](OpenTicketItemView.md) |  | 
**notes** | Option<**String**> |  | [optional]
**opened_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**opened_by** | **uuid::Uuid** |  | 
**opened_by_name** | Option<**String**> |  | [optional]
**order_id** | Option<**uuid::Uuid**> |  | [optional]
**ready** | Option<**bool**> | The kitchen has plated every line of every round. DERIVED from the ticket's `kitchen_tickets` at read time, so it is always what the KDS says now. `false` for a ticket nothing was ever fired to the kitchen for (routing mode `off`): there is nothing to be ready. | [optional]
**ready_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | The last moment the kitchen had the whole ticket plated. History for the timing reports; `ready` is the live fact. | [optional]
**settled_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**status** | **String** | The bill: `open`, `settled` or `voided`. Never `ready` — see [`Self::ready`]. | 
**subtotal** | **i32** |  | 
**table_id** | Option<**uuid::Uuid**> |  | [optional]
**ticket_ref** | Option<**String**> |  | [optional]
**void_note** | Option<**String**> |  | [optional]
**void_reason** | Option<**String**> | Categorised like an order void, so void-rate reports read dine-in and counter alike. | [optional]
**voided_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


