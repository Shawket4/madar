# CrmMember

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**apple_devices** | **i64** | Apple devices holding the card. | 
**balance** | **i32** | Track 1's balance in the programme's currency. | 
**birth_month** | Option<**i32**> |  | [optional]
**enrolled_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**google_card** | **bool** | A Google Wallet object was created for them. | 
**id** | **uuid::Uuid** |  | 
**last_visit_at** | **chrono::DateTime<chrono::FixedOffset>** | Their latest stamp, point or reward (or when they joined). | 
**lifetime** | **i32** |  | 
**locale** | **String** |  | 
**marketing_opt_out** | **bool** |  | 
**name** | **String** |  | 
**phone** | **String** |  | 
**rewards_ready** | **i32** | Rewards earned on track 1, not yet taken. | 
**tracks** | Option<[**Vec<models::MemberTrack>**](MemberTrack.md)> | Every track, when the card has more than one. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


