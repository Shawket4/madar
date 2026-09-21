# OrderNowFull

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addresses** | [**Vec<models::OrderNowAddress>**](OrderNowAddress.md) | Most recently used first. | 
**customer_id** | **uuid::Uuid** |  | 
**last_branch** | Option<[**models::OrderNowBranch**](OrderNowBranch.md)> | Derived from the latest order; `None` before the first one. | [optional]
**last_payment_hint** | Option<**String**> | `cash` | `card`, as they last said. | [optional]
**locale** | **String** |  | 
**name** | **String** |  | 
**phone** | **String** | Canonical (`2010…`). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


