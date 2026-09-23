# PunchFor

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**employee_id** | **uuid::Uuid** |  | 
**offline** | Option<[**models::OfflineStamp**](OfflineStamp.md)> | Set when the manager's phone queued the punch offline: it is dated at its own time, not when the phone got a signal back (audit 03 bug 6). | [optional]
**reason** | **String** | Required (CL-13): a dead phone, a forgotten one. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


