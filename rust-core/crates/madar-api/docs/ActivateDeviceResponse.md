# ActivateDeviceResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**device** | [**models::Device**](Device.md) |  | 
**device_token** | **String** | The device's own credential. Returned ONCE; store it in the device vault. Sent later as `X-Madar-Device-Token`. | 
**org_id** | **uuid::Uuid** |  | 
**org_name** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


