# CheckOutRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**accuracy_meters** | Option<**f64**> | The fix's reported accuracy, metres (CL-9). | [optional]
**is_mock** | Option<**bool**> | The OS's mock-location marker for this fix (CL-9). | [optional]
**latitude** | Option<**f64**> |  | [optional]
**longitude** | Option<**f64**> |  | [optional]
**offline** | Option<[**models::OfflineStamp**](OfflineStamp.md)> | Set when the punch was queued offline; the server rebuilds its time (CL-11). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


