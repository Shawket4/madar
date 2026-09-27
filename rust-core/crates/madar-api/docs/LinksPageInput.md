# LinksPageInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branches** | Option<[**Vec<models::LinksPageBranchInput>**](LinksPageBranchInput.md)> |  | [optional]
**items** | [**Vec<models::LinksPageItem>**](LinksPageItem.md) |  | 
**show_branches** | Option<**bool**> |  | [optional]
**show_cover** | Option<**bool**> |  | [optional]
**social_links** | Option<**serde_json::Value**> | The organisation's social links — the SAME map `PATCH /orgs/{id}` takes, stored in the same column, under the same closed list and https rule. Omitted = unchanged. | [optional]
**tagline_ar** | Option<**String**> |  | [optional]
**tagline_en** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


