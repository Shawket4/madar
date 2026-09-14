# \DevicesApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**list_client_versions**](DevicesApi.md#list_client_versions) | **GET** /devices/client-versions | 
[**list_devices**](DevicesApi.md#list_devices) | **GET** /devices | 
[**register_device**](DevicesApi.md#register_device) | **POST** /devices/register | 
[**update_device**](DevicesApi.md#update_device) | **PATCH** /devices/{id} | 



## list_client_versions

> Vec<models::ClientSeen> list_client_versions(legacy_only, days, branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**legacy_only** | Option<**bool**> | Only clients that took a legacy path within the window (default `true`). |  |
**days** | Option<**i32**> | Look-back window in days, 1..=365 (default 14 — the G-old gate). |  |
**branch_id** | Option<**uuid::Uuid**> | Narrow to one branch. |  |

### Return type

[**Vec<models::ClientSeen>**](ClientSeen.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_devices

> Vec<models::Device> list_devices(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::Device>**](Device.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## register_device

> models::Device register_device(register_device_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**register_device_request** | [**RegisterDeviceRequest**](RegisterDeviceRequest.md) |  | [required] |

### Return type

[**models::Device**](Device.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_device

> models::Device update_device(id, update_device_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Device id | [required] |
**update_device_request** | [**UpdateDeviceRequest**](UpdateDeviceRequest.md) |  | [required] |

### Return type

[**models::Device**](Device.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

