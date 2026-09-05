# TableBookingHint

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**booking_id** | **uuid::Uuid** |  | 
**ends_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**guest_name** | **String** |  | 
**held_from** | **chrono::DateTime<chrono::FixedOffset>** | `starts_at - hold_minutes`: from here the table reads as held. | 
**party_size** | **i32** |  | 
**starts_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**status** | **String** | `confirmed` | `seated`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


