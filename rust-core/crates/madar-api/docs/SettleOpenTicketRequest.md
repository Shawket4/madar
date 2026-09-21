# SettleOpenTicketRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_tendered** | Option<**i32**> |  | [optional]
**change_given** | Option<**i32**> | What the till handed back. Recorded as the drawer saw it, like a counter sale's; absent, it is derived from `amount_tendered` and the server's total. | [optional]
**customer_id** | Option<**uuid::Uuid**> | The customer this sale belongs to, when the cashier attached one at settle. Same rules as `customer_id` on an order (needs `customers.attach`; merged ids resolve; unknown ids are ignored). Absent, the sale takes the bill's own customer, if it has one. | [optional]
**discount_amount** | Option<**i32**> | What the till actually took off this bill, in minor units — the figure the drawer charged. Additive; absent, the server computes it as before. This is also what a replayed bill keeps when its preset has since been switched off: the money as rung, never recomputed from a dead rule. | [optional]
**discount_applied_by** | Option<**uuid::Uuid**> | Who put the discount on the bill. Read on replay (live, it is the cashier holding the token). Additive. | [optional]
**discount_approval_id** | Option<**uuid::Uuid**> | The manager approval that let the bill's discount past the cashier's cap, verified at replay like a counter sale's. Additive. | [optional]
**discount_id** | Option<**uuid::Uuid**> | Settle-time discount. ABSENT (all three fields) means the waiter's ticket discount is inherited, as it always was — but the till can now see that discount on the ticket view. The literal `discount_type: \"none\"` settles with no discount at all; any other value (or a `discount_id`) replaces the waiter's. | [optional]
**discount_kind** | Option<**String**> | Which discount act this bill performs: `preset` | `manual_amount` | `manual_percent`. A table bill is gated exactly like a counter sale, so it names its act in the same vocabulary. ADDITIVE — an older tablet sends nothing and the kind is derived as it always was (a `discount_id` means preset, an ad-hoc discount is manual of its type). | [optional]
**discount_percent_bps** | Option<**i32**> | Basis points for a percentage bill discount (1250 = 12.5%). Additive. | [optional]
**discount_type** | Option<**String**> |  | [optional]
**discount_value** | Option<**f64**> |  | [optional]
**live_approval** | Option<[**models::ReplayApproval**](ReplayApproval.md)> | A manager's one-time PIN approval for the LIVE settle route (owner, 2026-09-17), same shape and same verification as the replay one. Additive. | [optional]
**loyalty_customer_id** | Option<**uuid::Uuid**> | The member spending a balance on this settle, when rewards are applied. | [optional]
**loyalty_redemptions** | Option<[**Vec<models::LoyaltyRedemptionInput>**](LoyaltyRedemptionInput.md)> | Rewards covering lines of the ticket. A table-service bill redeems exactly like a counter one — the cashier scans at settle either way. | [optional]
**payment_method** | **String** |  | 
**payment_splits** | Option<[**Vec<models::PaymentSplitInput>**](PaymentSplitInput.md)> | Split tenders, when the party paid with more than one. Carried to the order's payment legs like a counter sale's; they must sum to the total. | [optional]
**settled_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the bill was paid, as the till says. An offline settle replayed later keeps its real time — it becomes the order's `created_at` and the ticket's `settled_at`, one instant on both rows. Absent means now; a future clock is refused. | [optional]
**till_id** | **uuid::Uuid** |  | 
**tip_amount** | Option<**i32**> |  | [optional]
**tip_payment_method** | Option<**String**> |  | [optional]
**total_amount** | Option<**i32**> | What the till says the bill came to — the figure its drawer collected. Checked against the server's own total exactly as a counter checkout is (`create_order_inner`'s drift check); a disagreement is refused, not recorded. Absent on older builds, which then get no check. The figure to send is `OpenTicketView::bill.total`, which is priced by the same engine under the same policy — a till that shows that number cannot disagree with the books. | [optional]
**waive_service_charge** | Option<**bool**> | Remove the service charge from this bill. Only someone whose effective permissions include `orders:waive_service` may send `true`; anyone else is refused, live or replayed. The order records who and when. Absent (every build before 0.7.2) means the charge stands. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


