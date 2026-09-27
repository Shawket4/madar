# LinksPageSettings

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branches** | [**Vec<models::LinksPageBranch>**](LinksPageBranch.md) | Every active branch, with its settings. | 
**card_image_url** | Option<**String**> | The shop's card image, which the page uses as its cover. | [optional]
**custom_branding** | **bool** | Whether the shop wears its own colours on the page. | 
**items** | [**Vec<models::LinksPageItem>**](LinksPageItem.md) |  | 
**loyalty_mode** | Option<**String**> |  | [optional]
**modules** | [**Vec<models::LinksModuleStatus>**](LinksModuleStatus.md) |  | 
**public_url** | Option<**String**> | Where the page is: the root of the shop's own host, for a shop on the branding tier with a slug. `None` otherwise — there is no generic links host. | [optional]
**show_branches** | **bool** |  | 
**show_cover** | **bool** |  | 
**social_links** | **serde_json::Value** | `organizations.social_links`, as stored. | 
**tagline_ar** | Option<**String**> |  | [optional]
**tagline_en** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


