# OpenCover

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**accuracy_meters** | Option<**f64**> | The fix's reported accuracy, metres (CL-9). | [optional]
**employee_id** | **uuid::Uuid** | Whose shift. | 
**is_mock** | Option<**bool**> | The OS's mock-location marker for this fix (CL-9). | [optional]
**latitude** | Option<**f64**> |  | [optional]
**longitude** | Option<**f64**> |  | [optional]
**offline** | Option<[**models::OfflineStamp**](OfflineStamp.md)> | Set when the cover was queued offline: it starts at its own time, not when the phone got a signal back (CL-11, audit 03 bug 6). | [optional]
**work_shift_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


