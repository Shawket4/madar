# SettleOpenTicketRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_tendered** | Option<**i32**> |  | [optional]
**change_given** | Option<**i32**> | What the till handed back. Recorded as the drawer saw it, like a counter sale's; absent, it is derived from `amount_tendered` and the server's total. | [optional]
**discount_id** | Option<**uuid::Uuid**> | Settle-time discount. ABSENT (all three fields) means the waiter's ticket discount is inherited, as it always was — but the till can now see that discount on the ticket view. The literal `discount_type: \"none\"` settles with no discount at all; any other value (or a `discount_id`) replaces the waiter's. | [optional]
**discount_type** | Option<**String**> |  | [optional]
**discount_value** | Option<**f64**> |  | [optional]
**loyalty_customer_id** | Option<**uuid::Uuid**> | The member spending a balance on this settle, when rewards are applied. | [optional]
**loyalty_redemptions** | Option<[**Vec<models::LoyaltyRedemptionInput>**](LoyaltyRedemptionInput.md)> | Rewards covering lines of the ticket. A table-service bill redeems exactly like a counter one — the cashier scans at settle either way. | [optional]
**payment_method** | **String** |  | 
**payment_splits** | Option<[**Vec<models::PaymentSplitInput>**](PaymentSplitInput.md)> | Split tenders, when the party paid with more than one. Carried to the order's payment legs like a counter sale's; they must sum to the total. | [optional]
**settled_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the bill was paid, as the till says. An offline settle replayed later keeps its real time — it becomes the order's `created_at` and the ticket's `settled_at`, one instant on both rows. Absent means now; a future clock is refused. | [optional]
**shift_id** | **uuid::Uuid** |  | 
**tip_amount** | Option<**i32**> |  | [optional]
**tip_payment_method** | Option<**String**> |  | [optional]
**total_amount** | Option<**i32**> | What the till says the bill came to — the figure its drawer collected. Checked against the server's own total exactly as a counter checkout is (`create_order_inner`'s drift check); a disagreement is refused, not recorded. Absent on older builds, which then get no check. The figure to send is `OpenTicketView::bill.total`, which is priced by the same engine under the same policy — a till that shows that number cannot disagree with the books. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


