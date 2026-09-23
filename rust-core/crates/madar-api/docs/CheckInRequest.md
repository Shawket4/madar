# CheckInRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**accuracy_meters** | Option<**f64**> | The fix's reported accuracy, metres (CL-9: a perfect one is suspicious). | [optional]
**branch_id** | **uuid::Uuid** |  | 
**is_mock** | Option<**bool**> | The OS's mock-location marker for this fix (CL-9). | [optional]
**latitude** | Option<**f64**> | Device coordinates. Required whenever the org enforces the geofence. | [optional]
**longitude** | Option<**f64**> |  | [optional]
**offline** | Option<[**models::OfflineStamp**](OfflineStamp.md)> | Set when the punch was queued offline; the server rebuilds its time (CL-11). | [optional]
**tracking_off** | Option<**bool**> | \"Always\" location was refused: the shift is marked and the manager told (CL-5). Location at the punch is still required. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


