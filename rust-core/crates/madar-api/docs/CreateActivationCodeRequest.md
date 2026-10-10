# CreateActivationCodeRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**kind** | Option<[**models::DeviceKind**](DeviceKind.md)> | `pos` (default) | `kds` | `waiter` | [optional]
**label** | Option<**String**> | A name for the tablet it is meant for (\"Front counter\"). | [optional]
**slot_id** | Option<**uuid::Uuid**> | A slot of the branch plan (`GET /branch-plan`). The code takes the slot's kind and name, and the device that uses it fills the slot. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


