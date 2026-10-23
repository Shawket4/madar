# AwardResult

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**already_awarded** | **bool** | True when this order had already earned — a double tap, a retry, or a replayed offline op. Not an error: the outcome is the one that was asked for, and the response carries the balance that resulted. | 
**member** | [**models::MemberView**](MemberView.md) |  | 
**order_id** | **uuid::Uuid** |  | 
**points_awarded** | **i32** | Points this sale earned. 0 when it was too small to reach one point. | 
**tracks** | Option<[**Vec<models::TrackAward>**](TrackAward.md)> | What each stamp track 2–4 earned on this press (0 for one already earned), when the card has more than one track. `points_awarded` and `member` stay track 1's. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


