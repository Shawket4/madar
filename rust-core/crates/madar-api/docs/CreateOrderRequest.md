# CreateOrderRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_tendered** | Option<**i32**> |  | [optional]
**branch_id** | **uuid::Uuid** |  | 
**change_given** | Option<**i32**> |  | [optional]
**created_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**customer_id** | Option<**uuid::Uuid**> | A manual customer (phase 6), attached when the actor holds `customers.attach`. A merged id resolves; an unknown one is ignored — a sale is never refused over its customer. | [optional]
**customer_name** | Option<**String**> |  | [optional]
**deals** | Option<[**Vec<models::DealApplicationInput>**](DealApplicationInput.md)> | Deals the teller applied (combos module, C8). Each names order lines by index and the units it takes. Needs `orders.deals.apply`. Additive. | [optional]
**device_code** | Option<**String**> | The device's code; with `device_id` + `order_number` the number is stored verbatim. | [optional]
**device_id** | Option<**uuid::Uuid**> | The device ringing the order (else `X-Madar-Device`). | [optional]
**discount_amount** | Option<**i32**> |  | [optional]
**discount_applied_by** | Option<**uuid::Uuid**> | Who put the discount on the sale (the signed-in till person). Read on replay only; live, it is the caller. Additive. | [optional]
**discount_approval_id** | Option<**uuid::Uuid**> | The manager approval (`approval.id` on the replay envelope) that let the discount past the person's cap. Additive. | [optional]
**discount_id** | Option<**uuid::Uuid**> |  | [optional]
**discount_kind** | Option<**String**> | Which discount act this is: `preset` | `manual_amount` | `manual_percent`. Absent (older clients): a `discount_id` means preset, an ad-hoc discount is manual of its type. Additive. | [optional]
**discount_percent_bps** | Option<**i32**> | The percentage asked for, in basis points (1250 = 12.5%). Additive. | [optional]
**discount_type** | Option<**String**> |  | [optional]
**discount_value** | Option<**f64**> |  | [optional]
**idempotency_key** | Option<**uuid::Uuid**> |  | [optional]
**items** | [**Vec<models::OrderItemInput>**](OrderItemInput.md) |  | 
**live_approval** | Option<[**models::ReplayApproval**](ReplayApproval.md)> | A manager's one-time PIN approval for the LIVE route (owner, 2026-09-17): the offline queue has always carried an `approval` on the replay envelope; this is the same object, sent with the live request instead, so a live over-cap discount need not queue to be approved. Verified the same way replay verifies one; `discount_approval_id` above is set from its `id` once verified. Additive. | [optional]
**loyalty_customer_id** | Option<**uuid::Uuid**> | The loyalty member spending a balance on this sale. Required when `loyalty_redemptions` is non-empty, and ONLY for that: earning is a separate, later act (`POST /loyalty/award`), so a sale that redeems nothing never names a member here. | [optional]
**loyalty_redemptions** | Option<[**Vec<models::LoyaltyRedemptionInput>**](LoyaltyRedemptionInput.md)> | Rewards covering lines of this cart. Each names a line by its index in `items` and how many of that line's units the reward pays for, so a mixed basket can have one free coffee among four paid ones. | [optional]
**notes** | Option<**String**> |  | [optional]
**order_number** | Option<**i32**> | The device's own order number (contract R4): its per-business-day sequence, the same counter as the `NNNN` of its `order_ref`. Stored VERBATIM when the request also names `device_id` and a non-blank `device_code` — the order then reads `display_number` `<device_code>-<n>`. Without all three (old clients, dashboard, delivery) it is ignored and the server numbers the sale per till: `MAX(order_number)+1` over the till's server-numbered orders, under the till advisory lock (`uq_orders_till_legacy_number`). | [optional]
**order_ref** | Option<**String**> | Client-minted order reference (`<BRANCH>-<YYMMDD>-<DEVICE>-<NNNN>`). Stored verbatim when present; absent → the server mints the deterministic shift-based ref. The global `UNIQUE(order_ref)` index keeps both paths collision-safe (a managed per-device code makes concurrent tills unique). | [optional]
**payment_method** | **String** |  | 
**payment_splits** | Option<[**Vec<models::PaymentSplitInput>**](PaymentSplitInput.md)> |  | [optional]
**service_mode** | Option<**String**> | Where the drink is going: `\"takeaway\"` (default) or `\"dine_in\"`. NOT `order_type`: that is derived from whether a waiter's ticket was settled and decides the service charge. This says only whether the customer is drinking in — so a counter shop with no floor can say it — and its only effect is that packaging (cups, lids, straws) is not deducted from stock. Absent ⇒ takeaway, which is what every client before this did. | [optional]
**started_by** | Option<**uuid::Uuid**> | The person who started this sale's cart, when the till says it was not the person ringing it (a held order resumed after a teller switch). Recorded when it names someone of the same org; anything else is dropped with a warning, never refused. Additive; older tills omit it. | [optional]
**subtotal** | Option<**i32**> |  | [optional]
**tax_amount** | Option<**i32**> |  | [optional]
**till_id** | **uuid::Uuid** |  | 
**tip_amount** | Option<**i32**> |  | [optional]
**tip_payment_method** | Option<**String**> |  | [optional]
**total_amount** | Option<**i32**> |  | [optional]
**verification** | Option<**String**> | `server` | `lan` | `unverified` — the till's verification as the device knew it. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


