# TillReconciliationLine

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**changed_after_close** | **bool** | `current_system_total <> system_total` — a late replay moved the total. | 
**current_system_total** | **i32** |  | 
**declared_amount** | Option<**i32**> |  | [optional]
**is_cash** | **bool** |  | 
**method** | **String** |  | 
**note** | Option<**String**> |  | [optional]
**order_count** | **i32** |  | 
**payment_method_id** | Option<**uuid::Uuid**> |  | [optional]
**reconciled_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**reconciled_by** | Option<**uuid::Uuid**> |  | [optional]
**status** | **String** | `checked` | `disagreed` | `unreviewed` | 
**system_total** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


