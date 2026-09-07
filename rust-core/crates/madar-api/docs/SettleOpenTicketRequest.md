# SettleOpenTicketRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_tendered** | Option<**i32**> |  | [optional]
**discount_id** | Option<**uuid::Uuid**> | Settle-time overrides (else the ticket's own discount / no tip). | [optional]
**discount_type** | Option<**String**> |  | [optional]
**discount_value** | Option<**i32**> |  | [optional]
**loyalty_customer_id** | Option<**uuid::Uuid**> | The member spending a balance on this settle, when rewards are applied. | [optional]
**loyalty_redemptions** | Option<[**Vec<models::LoyaltyRedemptionInput>**](LoyaltyRedemptionInput.md)> | Rewards covering lines of the ticket. A table-service bill redeems exactly like a counter one — the cashier scans at settle either way. | [optional]
**payment_method** | **String** |  | 
**shift_id** | **uuid::Uuid** |  | 
**tip_amount** | Option<**i32**> |  | [optional]
**tip_payment_method** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


