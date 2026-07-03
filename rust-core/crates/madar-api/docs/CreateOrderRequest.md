# CreateOrderRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_tendered** | Option<**i32**> |  | [optional]
**branch_id** | **uuid::Uuid** |  | 
**change_given** | Option<**i32**> |  | [optional]
**created_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**customer_name** | Option<**String**> |  | [optional]
**discount_amount** | Option<**i32**> |  | [optional]
**discount_id** | Option<**uuid::Uuid**> |  | [optional]
**discount_type** | Option<**String**> |  | [optional]
**discount_value** | Option<**i32**> |  | [optional]
**idempotency_key** | Option<**uuid::Uuid**> |  | [optional]
**items** | [**Vec<models::OrderItemInput>**](OrderItemInput.md) |  | 
**notes** | Option<**String**> |  | [optional]
**order_number** | Option<**i32**> | IGNORED by the server (accepted for backward compatibility only). The authoritative per-shift number is ALWAYS `MAX(order_number)+1` computed under the shift advisory lock — never the client value, which is used only on the device's local receipt. The byte-identical-at-reprint guarantee rides on `order_ref`, not this field. Two tills on one shift get distinct numbers (UNIQUE(shift_id, order_number) + the lock). | [optional]
**order_ref** | Option<**String**> | Client-minted order reference (`<BRANCH>-<YYMMDD>-<DEVICE>-<NNNN>`). Stored verbatim when present; absent → the server mints the deterministic shift-based ref. The global `UNIQUE(order_ref)` index keeps both paths collision-safe (a managed per-device code makes concurrent tills unique). | [optional]
**payment_method** | **String** |  | 
**payment_splits** | Option<[**Vec<models::PaymentSplitInput>**](PaymentSplitInput.md)> |  | [optional]
**shift_id** | **uuid::Uuid** |  | 
**subtotal** | Option<**i32**> |  | [optional]
**tax_amount** | Option<**i32**> |  | [optional]
**tip_amount** | Option<**i32**> |  | [optional]
**tip_payment_method** | Option<**String**> |  | [optional]
**total_amount** | Option<**i32**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


