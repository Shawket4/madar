# CreateCustomerRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | The branch where the customer was added (a till sends its own). | [optional]
**id** | Option<**uuid::Uuid**> | Client-minted id; a repeat with the same id returns the stored customer. | [optional]
**loyalty_customer_id** | Option<**uuid::Uuid**> |  | [optional]
**name** | **String** |  | 
**notes** | Option<**String**> |  | [optional]
**phone** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


