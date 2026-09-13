# CloseTillRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cash_note** | Option<**String**> |  | [optional]
**closed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**closing_cash_declared** | **i32** |  | 
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**reconciliation** | Option<[**Vec<models::ReconciliationInput>**](ReconciliationInput.md)> | Absent (old clients) → every used method is stored `unreviewed`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


