# CardDesignView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**colours** | [**models::Colours**](Colours.md) | The pass colours the shop has today. | 
**ctx** | [**models::Ctx**](Ctx.md) | What designs are checked against: mode, tracks, photo. | 
**custom_branding** | **bool** | False: the shop wears Madar's palette (custom branding is a super admin's switch) — the designer locks the colours and the photograph. | 
**default_design** | [**models::CardDesign**](CardDesign.md) | The design a shop starts from (madar-card's default for it). | 
**draft** | Option<[**models::CardDesign**](CardDesign.md)> | The design being edited, if one was saved. | [optional]
**logo_url** | Option<**String**> |  | [optional]
**photo_url** | Option<**String**> | The shop's card photograph and logo (upload URLs) for the live preview. | [optional]
**programme_name** | **String** |  | 
**programme_name_ar** | Option<**String**> |  | [optional]
**published** | Option<[**models::CardDesign**](CardDesign.md)> | The design the passes wear; `None` = the classic look (or, with several tracks, the automatic one). | [optional]
**published_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**revision** | **i32** |  | 
**stamp_unit** | **String** | What a unit of the card counts: `points`, `order`, `item` or `stamp`. | 
**tracks** | [**Vec<models::Track>**](Track.md) | The tracks, for labels and colours in the preview. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


