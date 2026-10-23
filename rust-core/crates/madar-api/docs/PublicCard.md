# PublicCard

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**design** | [**models::CardDesign**](CardDesign.md) |  | 
**revision** | **i32** | The published revision (0: the automatic multi-track design). | 
**stamp_unit** | **String** | `points`, `order`, `item` or `stamp` (madar-card `text::stamp_unit`). | 
**track_one_size** | **i32** | Track 1's size: the programme's card size. | 
**tracks** | [**Vec<models::Track>**](Track.md) | The tracks, without their menu items. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


