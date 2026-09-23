# \PushApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**delete_push_token**](PushApi.md#delete_push_token) | **DELETE** /push/token | 
[**set_push_token**](PushApi.md#set_push_token) | **PUT** /push/token | 



## delete_push_token

> delete_push_token(unregister_push_device)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**unregister_push_device** | [**UnregisterPushDevice**](UnregisterPushDevice.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_push_token

> set_push_token(register_push_device)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**register_push_device** | [**RegisterPushDevice**](RegisterPushDevice.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

