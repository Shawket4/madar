# TillPersonLine

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**name** | Option<**String**> | Their name (`users.name`); `null` when there is no such person. | [optional]
**order_count** | **i64** |  | 
**person_id** | Option<**uuid::Uuid**> | The person picked at checkout, else whoever was signed in; `null` for sales with nobody on them. | [optional]
**tips** | **i64** |  | 
**total** | **i64** | The sales' tenders (the payment summary's figure), minor units. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


