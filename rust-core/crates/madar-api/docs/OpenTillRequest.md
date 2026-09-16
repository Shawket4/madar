# OpenTillRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**device_id** | Option<**uuid::Uuid**> | Else the `X-Madar-Device` header. | [optional]
**edit_reason** | Option<**String**> |  | [optional]
**id** | Option<**uuid::Uuid**> |  | [optional]
**opened_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**opening_cash** | **i32** |  | 
**opening_cash_edited** | Option<**bool**> | Ignored. The server decides whether the opening was an edit, from its own expected carryover — a stale device computes this against a figure that has since moved on. Kept so older tablets keep parsing. | [optional]
**verification** | Option<[**models::TillVerification**](TillVerification.md)> | Ignored on the live route (live writes `server`). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


