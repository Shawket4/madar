# VoidOrderRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**note** | Option<**String**> | Free-text explanation. Required when `reason` is \"other\". | [optional]
**reason** | **String** |  | 
**restore_inventory** | Option<**bool**> | Ignored: a void always puts the sale's stock back. Kept so older tills that still send it are read, not refused. | [optional]
**voided_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


