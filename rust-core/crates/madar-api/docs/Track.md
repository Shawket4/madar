# Track

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cap** | Option<**i32**> | Tracks 2–4: the balance ceiling (a stamp past it is trimmed); at least the track's size. `None` = no ceiling. | [optional]
**colour** | Option<**String**> | This track's colour (`#RRGGBB`), else the pass's foreground. | [optional]
**items** | Option<**Vec<String>**> | Tracks 2–4: the menu items (ids) a sale earns on and a completed card covers. Empty = a counter-only track. Always empty on track 1, whose items are the programme's earning list and reward catalogue. | [optional]
**name_ar** | Option<**String**> |  | [optional]
**name_en** | Option<**String**> | Shown on the pass and the teller page; required from track 2 on. | [optional]
**per_item** | Option<**bool**> | Tracks 2–4: a stamp per unit of its items (default), or one per sale holding any. Track 1 follows the programme's own setting. | [optional]
**position** | **u32** | 1 to 4, in order. Track 1 is the programme's own counter. | 
**shape** | Option<[**models::StampShape**](StampShape.md)> | This track's stamp, else the design's. | [optional]
**size** | Option<**i32**> | Stamps that fill this track's card. `None` on track 1, whose size is the programme's card size (one number, one place). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


