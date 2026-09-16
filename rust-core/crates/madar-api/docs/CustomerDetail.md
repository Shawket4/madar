# CustomerDetail

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**customer** | [**models::Customer**](Customer.md) |  | 
**merged_from** | **Vec<uuid::Uuid>** | Customers merged into this one. | 
**recent_orders** | [**Vec<models::CustomerOrder>**](CustomerOrder.md) |  | 
**resolved_from** | Option<**uuid::Uuid**> | Set when the id asked for was merged: the id that was asked for. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


