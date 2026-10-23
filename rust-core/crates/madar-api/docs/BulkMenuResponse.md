# BulkMenuResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**archived** | Option<[**models::BulkArchived**](BulkArchived.md)> | `replace` only. | [optional]
**dry_run** | **bool** |  | 
**import_id** | Option<**uuid::Uuid**> | The `menu_imports` row; `None` on a dry run. | [optional]
**mode** | [**models::BulkMode**](BulkMode.md) |  | 
**summary** | [**models::BulkSummary**](BulkSummary.md) | What was written (or, on a dry run, would be). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


