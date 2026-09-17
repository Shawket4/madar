# CloseTillRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cash_note** | Option<**String**> |  | [optional]
**closed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**closing_cash_declared** | **i32** |  | 
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**held_orders_left_open** | Option<**i32**> | Held orders (and open counter carts) still parked on the device when the teller chose to close anyway, and their total. Additive; older tills omit them. | [optional]
**held_orders_left_open_total** | Option<**i32**> |  | [optional]
**reconciliation** | Option<[**Vec<models::ReconciliationInput>**](ReconciliationInput.md)> | Absent (old clients) → every used method is stored `unreviewed`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


