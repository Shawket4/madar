# CreateAdvanceRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_piastres** | **i64** |  | 
**installments** | Option<**i32**> | Defaults to 1 — repaid in full from the next payslip. | [optional]
**reason** | Option<**String**> |  | [optional]
**user_id** | Option<**uuid::Uuid**> | Admin-only; omitted on `/staff/me/_*`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


