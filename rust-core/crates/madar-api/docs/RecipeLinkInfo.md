# RecipeLinkInfo

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**in_sync** | Option<**bool**> | For a copy: `true` when its stored lines equal the source's for every size label the copy has (lint F19, twin drift). `null` for an item that is not a copy. | [optional]
**linked_copy_ids** | **Vec<uuid::Uuid>** | Live items whose recipe follows this one. | 
**menu_item_id** | **uuid::Uuid** |  | 
**recipe_source_item_id** | Option<**uuid::Uuid**> | The item this one's recipe follows, or `null`. | [optional]
**recipe_source_item_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


