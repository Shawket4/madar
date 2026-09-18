# VoidOrderRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**live_approval** | Option<[**models::ReplayApproval**](ReplayApproval.md)> | A manager's on-the-spot unlock for a void the teller's own limits do not allow (someone else's sale, or one older than their window). Additive: an older till never sends it and is refused exactly as before. | [optional]
**note** | Option<**String**> | Free-text explanation. Required when `reason` is \"other\". | [optional]
**reason** | **String** |  | 
**restore_inventory** | Option<**bool**> | Ignored: a void always puts the sale's stock back. Kept so older tills that still send it are read, not refused. | [optional]
**voided_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


