# OfflineStamp

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**elapsed_ms** | **i64** | Time-since-boot elapsed from `server_time` to the event, in ms. | 
**gps_time** | Option<**chrono::DateTime<chrono::FixedOffset>**> | The GPS fix's own satellite time, when it had one. | [optional]
**rebooted** | Option<**bool**> | The phone restarted after `server_time`, so `elapsed_ms` means nothing. | [optional]
**server_time** | **chrono::DateTime<chrono::FixedOffset>** | The last server time the phone saw (a response's `Date`). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


