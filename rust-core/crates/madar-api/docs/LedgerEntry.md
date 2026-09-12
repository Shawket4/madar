# LedgerEntry

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**basis_piastres** | Option<**i32**> | Piastres the rule was applied to (earns only). | [optional]
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | Option<**String**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**currency** | **String** | `\"points\"` or `\"visits\"` — which balance this row moved. | 
**id** | **uuid::Uuid** |  | 
**kind** | **String** | `earn`, `redeem`, `adjust`, or `reverse_earn` / `reverse_redeem` / `reverse_adjust` — the last three undo the row named in `reverses_id`. | 
**note** | Option<**String**> |  | [optional]
**order_id** | Option<**uuid::Uuid**> |  | [optional]
**points** | **i32** |  | 
**reverses_id** | Option<**uuid::Uuid**> | For a reversal, the row it undoes. | [optional]
**reward_name** | Option<**String**> |  | [optional]
**source** | **String** | Why the row exists: `sale`, `redemption`, `void`, `refund`, `birthday`, `winback` or `manual`. What a till or a dashboard should print as the reason, instead of guessing from the kind and the note. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


