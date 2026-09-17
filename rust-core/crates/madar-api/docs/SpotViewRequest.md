# SpotViewRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**approval** | Option<[**models::SpotViewApproval**](SpotViewApproval.md)> | Live route: the one-time unlock, when the caller does not hold `till.cash_spot_check`. (Replay carries it on the envelope.) | [optional]
**approval_id** | Option<**uuid::Uuid**> | Set by replay from a verified envelope approval (ignored live). | [optional]
**approved_by** | Option<**uuid::Uuid**> | Set by replay from a verified envelope approval (ignored live). | [optional]
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**id** | Option<**uuid::Uuid**> | Client-minted id; a retry, a replay or the print of the same view is one row. | [optional]
**printed** | Option<**bool**> | The spot report was printed. | [optional]
**printed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**viewed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


