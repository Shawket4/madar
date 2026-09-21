# OrderNowBranch

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**channel** | **String** | The channel they last used there. | 
**id** | **uuid::Uuid** |  | 
**name** | **String** |  | 
**stale** | **bool** | True when it cannot be used as-is right now; the client falls back to its branch/channel chooser and keeps the rest of the prefill. | 
**stale_reason** | Option<**String**> | `branch_unavailable` | `channel_closed`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


