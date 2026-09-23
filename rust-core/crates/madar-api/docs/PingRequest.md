# PingRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**accuracy_meters** | Option<**f64**> |  | [optional]
**battery_percent** | Option<**i32**> |  | [optional]
**is_mock** | Option<**bool**> | The OS's own mock-location marker (Android `isMock`, iOS `isSimulatedBySoftware`) (CL-9). | [optional]
**latitude** | **f64** |  | 
**longitude** | **f64** |  | 
**offline** | Option<[**models::OfflineStamp**](OfflineStamp.md)> | Set when the ping was queued offline; the server rebuilds its time (CL-11). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


