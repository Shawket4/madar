# LintIssue

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**entity_id** | **uuid::Uuid** |  | 
**entity_name** | **String** |  | 
**entity_type** | **String** |  | 
**group_id** | Option<**uuid::Uuid**> | The modifier group the finding is about, when it is group-scoped. | [optional]
**item_id** | Option<**uuid::Uuid**> | The menu item the finding is about, when it is item-scoped. | [optional]
**message** | **String** |  | 
**rule** | **String** | Audit rule id, e.g. `F4`. | 
**severity** | [**models::LintSeverity**](LintSeverity.md) |  | 
**size_label** | Option<**String**> | Set when the finding is about one size of an item. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


