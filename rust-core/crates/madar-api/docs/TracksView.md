# TracksView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**mode** | **String** | `points` or `visits` (the org default's). | 
**stamp_unit** | **String** | What track 1 counts: `points`, `order`, `item` or `stamp` (tracks 2–4 count stamps). madar-card `text::stamp_unit`. | 
**track_one_size** | **i32** | Track 1's size: the programme's card size. | 
**tracks** | [**Vec<models::Track>**](Track.md) | Every track in position order; track 1 always first. In a points programme only track 1 (tracks 2–4 are kept but inactive). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


