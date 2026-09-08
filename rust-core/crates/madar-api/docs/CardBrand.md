# CardBrand

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**background_color** | Option<**String**> | `#RRGGBB`, validated on write. | [optional]
**card_image_url** | Option<**String**> | The wide photograph across the card — Apple's strip, Google's hero image, and the band at the top of the web card. Absent is a finished card, not a broken one. | [optional]
**foreground_color** | Option<**String**> |  | [optional]
**label_color** | Option<**String**> |  | [optional]
**logo_is_mark** | **bool** | True when the logo is a shape on transparency, so the card may repaint it in the foreground for contrast. False for a logo with its background baked in, which gets a plate to sit on instead — repainting that one would give a solid rectangle. See `orgs::branding::is_mark`. | 
**logo_url** | Option<**String**> |  | [optional]
**org_name** | **String** | The organisation's name. Always present. | 
**program_name** | **String** | What the programme calls itself (\"Rewards\", \"Bean Club\"). | 
**program_name_ar** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


