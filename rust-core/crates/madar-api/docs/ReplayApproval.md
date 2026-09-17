# ReplayApproval

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_minor** | Option<**i64**> |  | [optional]
**approver_id** | **uuid::Uuid** |  | 
**capability** | **String** | Capability key, e.g. `orders.void`. | 
**id** | **uuid::Uuid** |  | 
**percent_bps** | Option<**i64**> | Basis points, for an act capped by `max_percent` (a discount). Additive. | [optional]
**value_minor** | Option<**i64**> | The value an approval covered (`max_value` limits, e.g. a waste). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


