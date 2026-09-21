# UpdateCustomerRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**locale** | Option<**String**> | `en` or `ar`. Absent = unchanged. | [optional]
**loyalty_customer_id** | Option<**uuid::Uuid**> | DEPRECATED and ignored (see `CreateCustomerRequest`). | [optional]
**marketing_opt_out** | Option<**bool**> | Absent = unchanged. | [optional]
**name** | Option<**String**> |  | [optional]
**notes** | Option<**String**> | Absent = unchanged; `\"\"` clears. | [optional]
**phone** | Option<**String**> | Absent = unchanged; `\"\"` clears. | [optional]
**unlink_loyalty** | Option<**bool**> | DEPRECATED and ignored: leaving the programme is `DELETE /loyalty/members/{id}`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


