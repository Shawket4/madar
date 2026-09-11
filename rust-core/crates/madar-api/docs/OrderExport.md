# OrderExport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_tendered** | Option<**i32**> |  | [optional]
**branch_id** | **uuid::Uuid** |  | 
**change_given** | Option<**i32**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**customer_name** | Option<**String**> |  | [optional]
**delivery_channel** | Option<**String**> | Delivery channel (\"in_mall\" | \"outside\") of the linked delivery order, surfaced on the list so clients can flag + segment delivery orders without a per-order detail fetch. `null` for dine-in orders. | [optional]
**delivery_fee** | **i32** | Delivery charge in piastres, shown separately from the item subtotal. Always 0 for dine-in orders; for delivery orders `total_amount == subtotal + tax_amount + delivery_fee` (minus discount). | 
**delivery_lat** | Option<**f64**> | Customer location of the linked delivery order, so clients can link out to a map (e.g. Google Maps) without a per-order detail fetch. `null` for dine-in orders or delivery orders without captured coordinates. | [optional]
**delivery_lng** | Option<**f64**> |  | [optional]
**delivery_order_id** | Option<**uuid::Uuid**> | Links a finalized delivery order back to its `delivery_orders` row (customer, address, channel, zone). `null` for dine-in orders. | [optional]
**discount_amount** | **i32** |  | 
**discount_id** | Option<**uuid::Uuid**> |  | [optional]
**discount_type** | Option<**String**> |  | [optional]
**discount_value** | **f64** |  | 
**id** | **uuid::Uuid** |  | 
**notes** | Option<**String**> |  | [optional]
**order_number** | **i32** |  | 
**order_ref** | Option<**String**> | Human-readable, org-unique reference (e.g. \"DT-260614-0042\"). Additive alongside the per-shift order_number. Optional only during the rollout window before the historical backfill runs; never null afterwards. | [optional]
**order_type** | **String** | Order origin: \"dine_in\" (POS sale) or \"delivery\" (finalized delivery order). Defaults to \"dine_in\" for every POS sale. | 
**payment_legs** | [**Vec<models::PaymentLeg>**](PaymentLeg.md) | What was ACTUALLY tendered, one entry per `order_payments` row — the same rows every money report buckets by. A single-tender order has one leg; a split order has one per leg (e.g. card 285.00 + cash 255.00). Empty on the response to order creation, where the legs are written just after the row this statement returns; every read hydrates it. | 
**payment_method** | **String** | The order's NOMINAL payment label. For a split order this is the literal `'mixed'` — a label that exists in no money report, because reports bucket by what was actually tendered. Use [`Order::payment_legs`] for the real methods; treat this as a display badge only. | 
**service_charge_amount** | Option<**i32**> | The service charge on this bill; `0` where the branch charges none. Its own field, and its own receipt line: a charge the customer did not choose is stated separately from the tax rather than folded into it. | [optional]
**shift_id** | **uuid::Uuid** |  | 
**status** | **String** |  | 
**subtotal** | **i32** |  | 
**tax_amount** | **i32** |  | 
**teller_id** | **uuid::Uuid** |  | 
**teller_name** | **String** |  | 
**tip_amount** | Option<**i32**> |  | [optional]
**tip_payment_method** | Option<**String**> |  | [optional]
**total_amount** | **i32** |  | 
**void_note** | Option<**String**> |  | [optional]
**void_reason** | Option<**String**> |  | [optional]
**voided_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**voided_by** | Option<**uuid::Uuid**> |  | [optional]
**waiter_id** | Option<**uuid::Uuid**> | The WAITER who opened this order's ticket (`open_tickets.opened_by`), stamped server-side at settle time. `null` for direct teller sales and delivery orders (they never pass through a waiter's ticket). | [optional]
**waiter_name** | Option<**String**> |  | [optional]
**items** | [**Vec<models::OrderItemFull>**](OrderItemFull.md) |  | 
**payments** | [**Vec<models::OrderPayment>**](OrderPayment.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


