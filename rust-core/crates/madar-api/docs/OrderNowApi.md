# \OrderNowApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**order_now_combine**](OrderNowApi.md#order_now_combine) | **POST** /public/order-now/{token}/combine | 
[**order_now_context**](OrderNowApi.md#order_now_context) | **GET** /public/order-now/{token} | 
[**order_now_replace_identity**](OrderNowApi.md#order_now_replace_identity) | **POST** /public/order-now/{token}/replace-identity | 



## order_now_combine

> models::ReplaceIdentityResponse order_now_combine(token, replace_identity_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**token** | **String** | Member token — this customer survives | [required] |
**replace_identity_request** | [**ReplaceIdentityRequest**](ReplaceIdentityRequest.md) |  | [required] |

### Return type

[**models::ReplaceIdentityResponse**](ReplaceIdentityResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## order_now_context

> models::OrderNowContext order_now_context(token, device_token)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**token** | **String** | Member token (the card's QR) | [required] |
**device_token** | Option<**String**> | From `/public/otp/verify`, for the customer's current phone. Absent or not valid for that phone → the masked context. |  |

### Return type

[**models::OrderNowContext**](OrderNowContext.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## order_now_replace_identity

> models::ReplaceIdentityResponse order_now_replace_identity(token, replace_identity_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**token** | **String** | Member token | [required] |
**replace_identity_request** | [**ReplaceIdentityRequest**](ReplaceIdentityRequest.md) |  | [required] |

### Return type

[**models::ReplaceIdentityResponse**](ReplaceIdentityResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

