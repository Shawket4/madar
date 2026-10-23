# MenuDisplaySettings

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | The branch the shop picked; `None` = the default (its first branch). | [optional]
**branches** | [**Vec<models::MenuDisplayBranchOption>**](MenuDisplayBranchOption.md) | Every open branch, for the picker. | 
**effective_branch_id** | Option<**uuid::Uuid**> | The branch the page shows right now (the pick, else the default). `None` when the shop has no open branch. | [optional]
**enabled** | **bool** |  | 
**public_url** | Option<**String**> | Where the page is: `<slug>.madar-pos.cloud/menu` on a shop's own host, else the generic host's `/menu/<org id>`. `None` when no host is configured on this server. | [optional]
**title_ar** | Option<**String**> |  | [optional]
**title_en** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


