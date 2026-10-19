# ReadinessProblem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**entity_id** | **uuid::Uuid** |  | 
**entity_type** | **String** | `branch` | `item` | `attachment` | `option` | `ingredient`. | 
**group_id** | Option<**uuid::Uuid**> | The modifier group to open, when the problem is about one. | [optional]
**item_id** | Option<**uuid::Uuid**> | The item to open, when the problem is about one. | [optional]
**message** | Option<**String**> | The lint's sentence, English, for the menu-lint problems only. | [optional]
**name** | **String** |  | 
**rule** | Option<**String**> | The menu lint rule (`F1`…) when the problem comes from the lint. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


