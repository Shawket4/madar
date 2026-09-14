# OrderFull

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
**device_code** | Option<**String**> | That device's code (`36B`), stored with the order. `null` when server-numbered. | [optional]
**device_id** | Option<**uuid::Uuid**> | The device that numbered this sale (contract R4). `null` for server-numbered orders (old clients, dashboard, delivery). | [optional]
**discount_amount** | **i32** |  | 
**discount_id** | Option<**uuid::Uuid**> |  | [optional]
**discount_rate** | Option<**f64**> | The stored value — a fraction for a percentage. Same column as [`Order::discount_value`]. | [optional]
**discount_type** | Option<**String**> |  | [optional]
**discount_value** | **i64** | LEGACY SPELLING — an integer, 0-100 for a percentage. See `discounts::wire`: every shipped till was generated against `integer`, and a double here fails to deserialise the whole ORDER, not just this field. Read [`Order::discount_rate`] for the stored number. | 
**display_number** | Option<**String**> | What receipts and lists show: `<device_code>-<order_number>` (`36B-12`) for a device-numbered sale, else `order_number` as text. | [optional]
**id** | **uuid::Uuid** |  | 
**idempotency_key** | Option<**uuid::Uuid**> | The client-minted key the sale was created with (a till's sale, or the ticket id of a settled bill). An offline POS identifies its own row by it when a list read brings the sale back (OFFLINE_B_DESIGN §7). Additive. | [optional]
**loyalty_customer_id** | Option<**uuid::Uuid**> | The loyalty member this sale redeemed for (or was scanned for). | [optional]
**loyalty_member_name** | Option<**String**> | That member's name, for the order detail. `None` once forgotten. | [optional]
**notes** | Option<**String**> |  | [optional]
**open_ticket_id** | Option<**uuid::Uuid**> | The open ticket this sale settled, if any. Additive. | [optional]
**order_number** | **i32** |  | 
**order_ref** | Option<**String**> | Human-readable, org-unique reference (e.g. \"DT-260614-0042\"). Additive alongside the per-shift order_number. Optional only during the rollout window before the historical backfill runs; never null afterwards. | [optional]
**order_type** | **String** | What kind of sale: \"dine_in\" (settled from a waiter's ticket — the only kind that carries a service charge), \"takeaway\" (rung straight through the till) or \"delivery\" (a finalized delivery order). Till sales before 2026-09 say \"dine_in\" because \"takeaway\" could not be expressed. | 
**payment_legs** | [**Vec<models::PaymentLeg>**](PaymentLeg.md) | What was ACTUALLY tendered, one entry per `order_payments` row — the same rows every money report buckets by. A single-tender order has one leg; a split order has one per leg (e.g. card 285.00 + cash 255.00). Empty on the response to order creation, where the legs are written just after the row this statement returns; every read hydrates it. | 
**payment_method** | **String** | The order's NOMINAL payment label. For a split order this is the literal `'mixed'` — a label that exists in no money report, because reports bucket by what was actually tendered. Use [`Order::payment_legs`] for the real methods; treat this as a display badge only. | 
**price_expected_total** | Option<**i32**> | What the catalogue says this sale should have come to, when it differs. Beside `subtotal` it is the size of the drift, which is the question anyone looking at a flagged sale asks next. | [optional]
**price_flagged** | Option<**bool**> | This sale was rung against a catalogue that has since moved: a line was charged at a price the menu no longer says, or the item was disabled at this branch. Both mean a till that was OFFLINE when something changed — a live sale is priced by the server and cannot deviate.  Recorded, never rejected: the money already changed hands. It is here so the POS and the dashboard can SHOW it, which is the whole point of flagging something. | [optional]
**service_charge_amount** | Option<**i32**> | The service charge on this bill; `0` where the branch charges none. Its own field, and its own receipt line: a charge the customer did not choose is stated separately from the tax rather than folded into it. | [optional]
**shift_id** | **uuid::Uuid** | DEPRECATED: same value as `till_id` (required by POS v0.5.1/v0.6.0). | 
**status** | **String** |  | 
**subtotal** | **i32** |  | 
**tax_amount** | **i32** |  | 
**teller_id** | **uuid::Uuid** |  | 
**teller_name** | **String** |  | 
**till_id** | **uuid::Uuid** |  | 
**timezone** | Option<**String**> | The branch's effective IANA timezone (see `crate::tz`) — the zone every timestamp on this payload is shown and printed in. Additive: older clients ignore it; `null` only where a write path does not resolve it. | [optional]
**tip_amount** | Option<**i32**> |  | [optional]
**tip_payment_method** | Option<**String**> |  | [optional]
**total_amount** | **i32** |  | 
**verification** | Option<**String**> | `server` | `lan` | `unverified` — the till's verification as the ringing device knew it; `null` when not recorded. | [optional]
**void_note** | Option<**String**> |  | [optional]
**void_reason** | Option<**String**> |  | [optional]
**voided_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**voided_by** | Option<**uuid::Uuid**> |  | [optional]
**waiter_id** | Option<**uuid::Uuid**> | The WAITER who opened this order's ticket (`open_tickets.opened_by`), stamped server-side at settle time. `null` for direct teller sales and delivery orders (they never pass through a waiter's ticket). | [optional]
**waiter_name** | Option<**String**> |  | [optional]
**delivery** | Option<[**models::OrderDeliveryInfo**](OrderDeliveryInfo.md)> | Delivery context (customer phone, address, channel, zone), populated only on the single-order detail endpoint and only when the order originated from a delivery order. `null`/absent for dine-in orders. | [optional]
**items** | [**Vec<models::OrderItemFull>**](OrderItemFull.md) |  | 
**loyalty_redemption_refused** | Option<**String**> | Set only on the response to a REPLAYED sale whose rewards the points could not pay for: the covered lines stayed covered, no points moved, the order is flagged. The till shows this sentence to the teller. | [optional]
**warnings** | Option<**Vec<String>**> | Non-fatal warnings raised while placing the order — currently used to flag ingredients that were oversold (stock driven below zero). Empty for reads/refunds. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


