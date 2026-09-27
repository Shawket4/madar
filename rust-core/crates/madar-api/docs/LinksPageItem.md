# LinksPageItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | Option<**uuid::Uuid**> | Custom links only: a stable id, so the editor can tell two links with the same title apart. Minted by the server when missing. | [optional]
**kind** | [**models::LinksItemKind**](LinksItemKind.md) |  | 
**title_ar** | Option<**String**> | Custom links only. Falls back to the English title when empty. | [optional]
**title_en** | Option<**String**> | Custom links only. | [optional]
**url** | Option<**String**> | Custom links only — a full `https://` address. | [optional]
**visible** | Option<**bool**> | Off = kept in the list (and its place) but not shown. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


