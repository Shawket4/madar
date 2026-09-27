# PutModifierGroupsRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**groups** | Option<[**Vec<models::GroupAttachInput>**](GroupAttachInput.md)> | The item's full set of reusable groups, in order. `[]` detaches every group (the item then offers none). Omitted or `null` changes nothing, so a partial update or an older client never detaches by accident. The item's own priced options are not in this set: they belong to `PUT /menu-items/{id}/options`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


