# MemberWallet

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**apple_devices** | **i64** |  | 
**apple_registered_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**google_card** | **bool** |  | 
**marketing_opt_out** | **bool** |  | 
**messages_received** | **i64** | Dashboard messages this member was sent. | 
**notice** | Option<**String**> |  | [optional]
**notice_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**notice_seen_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Apple's device fetched the pass after the push. | [optional]
**notice_wallets** | Option<**String**> |  | [optional]
**pass_updated_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the pass was last rebuilt for them. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


