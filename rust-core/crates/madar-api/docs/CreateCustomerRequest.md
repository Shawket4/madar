# CreateCustomerRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | The branch where the customer was added (a till sends its own). | [optional]
**id** | Option<**uuid::Uuid**> | Client-minted id; a repeat with the same id returns the stored customer. | [optional]
**loyalty_customer_id** | Option<**uuid::Uuid**> | DEPRECATED and ignored: a membership shares the customer's id, so there is nothing to link. Accepted so deployed tills keep working. | [optional]
**name** | **String** |  | 
**notes** | Option<**String**> |  | [optional]
**phone** | Option<**String**> |  | [optional]
**source** | Option<**String**> | Where the customer came from. Defaults to `pos` when a branch is named (a till) and `dashboard` otherwise. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


