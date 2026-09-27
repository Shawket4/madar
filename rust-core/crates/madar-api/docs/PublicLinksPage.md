# PublicLinksPage

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branches** | [**Vec<models::PublicLinksBranch>**](PublicLinksBranch.md) | Empty when \"Visit us\" is off. | 
**brand** | [**models::PublicBrand**](PublicBrand.md) |  | 
**cover_image_url** | Option<**String**> | The card image, when the shop uses it as the cover (and is on the branding tier — the loader already applied that). | [optional]
**items** | [**Vec<models::PublicLinksItem>**](PublicLinksItem.md) | Visible, available buttons, in the shop's order. | 
**loyalty_mode** | Option<**String**> | `points` or `visits`, when the rewards button is shown. | [optional]
**socials** | [**Vec<models::PublicSocialLink>**](PublicSocialLink.md) |  | 
**tagline_ar** | Option<**String**> |  | [optional]
**tagline_en** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


