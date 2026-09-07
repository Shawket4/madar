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
**kind** | **String** |  | 
**note** | Option<**String**> |  | [optional]
**order_id** | Option<**uuid::Uuid**> |  | [optional]
**points** | **i32** |  | 
**reward_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


