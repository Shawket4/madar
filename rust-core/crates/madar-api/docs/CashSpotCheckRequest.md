# CashSpotCheckRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**approval_id** | Option<**uuid::Uuid**> | Replay only: the approval id carried on the envelope (ignored live). | [optional]
**approved_by** | Option<**uuid::Uuid**> | Replay only: the person whose PIN unlocked this check (ignored live). | [optional]
**checked_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**counted_cash** | **i64** | The cash counted in the drawer, minor units. | 
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**expected_cash** | Option<**i64**> | The expected cash the counter saw. Absent → the server computes it now. | [optional]
**id** | Option<**uuid::Uuid**> | Client-minted id; a retried or replayed check with the same id is one check. | [optional]
**methods** | Option<[**Vec<models::SpotCheckMethodInput>**](SpotCheckMethodInput.md)> | Per-method expected / counted figures. Absent → the server's own totals, uncounted. | [optional]
**note** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


