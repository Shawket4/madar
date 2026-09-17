# DiscountAuditEntry

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_minor** | **i64** |  | 
**applied_by_name** | Option<**String**> | Who applied it (the till operator for older sales). | [optional]
**approval_id** | Option<**uuid::Uuid**> |  | [optional]
**approved_by_name** | Option<**String**> |  | [optional]
**branch_name** | **String** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**flagged** | **bool** | The sale was replayed with a discount its author was not allowed and no valid manager approval (`authz_replay_flags`). | 
**kind** | Option<**String**> | `preset` | `manual_amount` | `manual_percent`, or `null` before attribution. | [optional]
**order_id** | **uuid::Uuid** |  | 
**order_ref** | Option<**String**> |  | [optional]
**percent_bps** | Option<**i32**> | Basis points, for a percentage. | [optional]
**preset_id** | Option<**uuid::Uuid**> |  | [optional]
**preset_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


