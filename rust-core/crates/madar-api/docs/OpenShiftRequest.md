# OpenShiftRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**edit_reason** | Option<**String**> |  | [optional]
**id** | Option<**uuid::Uuid**> |  | [optional]
**opened_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**opening_cash** | **i32** |  | 
**opening_cash_edited** | Option<**bool**> | Ignored by the server — the carryover edit is DERIVED from the previous shift's declared closing. Kept only for API/back-compat with clients. | [optional]
**till_id** | Option<**uuid::Uuid**> | The till (drawer) this shift opens on. Optional for back-compat: when omitted the server falls back to the branch's default till. Newer device-bound clients send their configured till explicitly. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


