# Refund

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount** | **i32** |  | 
**branch_id** | **uuid::Uuid** |  | 
**client_ref** | Option<**uuid::Uuid**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**is_cash** | **bool** | Whether `method` meant cash when the refund was issued. Snapshotted. | 
**issued_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**issued_by** | **uuid::Uuid** |  | 
**issued_by_name** | **String** |  | 
**method** | **String** |  | 
**note** | Option<**String**> |  | [optional]
**order_id** | **uuid::Uuid** |  | 
**reason** | **String** | One of the [`RefundReason`] spellings. | 
**service_charge_amount** | Option<**i32**> | How much of `amount` was service charge, the same way. Additive. | [optional]
**shift_id** | **uuid::Uuid** | DEPRECATED: same value as `till_id`. | 
**tax_amount** | Option<**i32**> | How much of `amount` was tax, taken back pro rata of the order's own tax (filled by the database, cumulatively across the order's refunds, so a full refund takes back exactly the order's tax). Additive. | [optional]
**till_id** | **uuid::Uuid** | The shift the refund was ISSUED in — the drawer the money left. Not necessarily the till the order was sold in. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


