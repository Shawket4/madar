# ActivateDeviceRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**app_version** | Option<**String**> |  | [optional]
**code** | **String** | The 8-digit code from the dashboard. | 
**device_code** | Option<**String**> | The device's short code on receipts (`T1`); a default is derived when absent or invalid. | [optional]
**device_id** | **uuid::Uuid** | The install's own id (the core's `lan_device_id`). | 
**platform** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


