# BroadcastInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**audience** | Option<[**models::Audience**](Audience.md)> |  | [optional]
**message** | [**models::Message**](Message.md) |  | 
**scheduled_for** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Absent = now. Otherwise 5 minutes to 30 days ahead. | [optional]
**whatsapp_fallback** | Option<**bool**> | Also WhatsApp members with no card in a wallet (costs the shop). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


