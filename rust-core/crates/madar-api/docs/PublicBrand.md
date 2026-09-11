# PublicBrand

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**accent_color** | **String** |  | 
**background_color** | **String** | `#RRGGBB`. Madar's own when the shop is not on the tier. | 
**card_image_url** | Option<**String**> |  | [optional]
**custom_branding** | **bool** | Whether the rest of this is the shop's or Madar's.  The page does not need it to render — the palette below is already resolved — but it decides how loudly Madar signs the footer. | 
**foreground_color** | **String** |  | 
**logo_is_mark** | **bool** | True when the logo is a shape on transparency and may be repainted for contrast. See `orgs::branding::is_mark`. | 
**logo_url** | Option<**String**> |  | [optional]
**name** | **String** | Always the shop's own name, at every tier. A page that does not say whose it is helps nobody, and that was never the thing being sold. | 
**org_id** | **uuid::Uuid** |  | 
**slug** | Option<**String**> | `None` when the shop has no address of its own — reached by `org_id`, which every page that already knows the shop uses. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


