# CreateAdvanceRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_piastres** | **i64** |  | 
**employee_id** | Option<**uuid::Uuid**> | Admin-only; omitted on `/staff/me/_*`. | [optional]
**installments** | Option<**i32**> | Defaults to 1 — repaid in full from the next payslip. | [optional]
**reason** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


