# \DevicesApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_code**](DevicesApi.md#create_code) | **POST** /devices/activation-codes | 
[**device_snapshot**](DevicesApi.md#device_snapshot) | **GET** /devices/me/authz-snapshot | 
[**list_client_versions**](DevicesApi.md#list_client_versions) | **GET** /devices/client-versions | 
[**list_codes**](DevicesApi.md#list_codes) | **GET** /devices/activation-codes | 
[**list_devices**](DevicesApi.md#list_devices) | **GET** /devices | 
[**register_device**](DevicesApi.md#register_device) | **POST** /devices/register | 
[**revoke_code**](DevicesApi.md#revoke_code) | **POST** /devices/activation-codes/{id}/revoke | 
[**update_device**](DevicesApi.md#update_device) | **PATCH** /devices/{id} | 



## create_code

> models::ActivationCode create_code(create_activation_code_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_activation_code_request** | [**CreateActivationCodeRequest**](CreateActivationCodeRequest.md) |  | [required] |

### Return type

[**models::ActivationCode**](ActivationCode.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## device_snapshot

> serde_json::Value device_snapshot(x_madar_device, x_madar_device_token)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**x_madar_device** | **String** | The device id | [required] |
**x_madar_device_token** | **String** | The credential issued at activation | [required] |

### Return type

[**serde_json::Value**](serde_json::Value.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


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


## list_codes

> Vec<models::ActivationCode> list_codes(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::ActivationCode>**](ActivationCode.md)

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


## revoke_code

> models::ActivationCode revoke_code(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Activation code id | [required] |

### Return type

[**models::ActivationCode**](ActivationCode.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
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

