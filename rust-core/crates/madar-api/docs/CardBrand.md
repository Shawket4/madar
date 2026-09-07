# CardBrand

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**background_color** | Option<**String**> | `#RRGGBB`, validated on write. | [optional]
**foreground_color** | Option<**String**> |  | [optional]
**label_color** | Option<**String**> |  | [optional]
**logo_is_mark** | **bool** | True when the logo is a shape on transparency, so the card may repaint it in the foreground for contrast. False for a logo with its background baked in, which gets a plate to sit on instead — repainting that one would give a solid rectangle. See `orgs::branding::is_mark`. | 
**logo_url** | Option<**String**> |  | [optional]
**org_name** | **String** | The organisation's name. Always present. | 
**program_name** | **String** | What the programme calls itself (\"Rewards\", \"Bean Club\"). | 
**program_name_ar** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


