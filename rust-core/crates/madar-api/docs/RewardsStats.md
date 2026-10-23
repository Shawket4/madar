# RewardsStats

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**active_members** | **i64** |  | 
**daily** | [**Vec<models::StatsDay>**](StatsDay.md) |  | 
**earned** | **i64** |  | 
**from** | **chrono::NaiveDate** |  | 
**members_total** | **i64** |  | 
**members_with_card** | **i64** | Members holding the card in a wallet (Apple device or Google object). | 
**messages_seen** | **i64** |  | 
**messages_sent** | **i64** | Messages that reached a card or WhatsApp (not \"no card, no WhatsApp\"). | 
**mode** | **String** | `points` or `visits`. | 
**new_members** | **i64** |  | 
**per_track** | [**Vec<models::StatsTrack>**](StatsTrack.md) |  | 
**redemptions** | **i64** |  | 
**stamp_unit** | **String** | What track 1 counts: `points`, `order`, `item` or `stamp` (tracks 2–4 count stamps). | 
**to** | **chrono::NaiveDate** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


