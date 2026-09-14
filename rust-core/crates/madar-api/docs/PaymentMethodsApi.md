# \PaymentMethodsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**activate_payment_method**](PaymentMethodsApi.md#activate_payment_method) | **POST** /payment-methods/{id}/activate | 
[**create_payment_method**](PaymentMethodsApi.md#create_payment_method) | **POST** /payment-methods | 
[**deactivate_payment_method**](PaymentMethodsApi.md#deactivate_payment_method) | **POST** /payment-methods/{id}/deactivate | 
[**get_availability**](PaymentMethodsApi.md#get_availability) | **GET** /payment-methods/availability | 
[**get_effective**](PaymentMethodsApi.md#get_effective) | **GET** /payment-methods/effective | 
[**list_payment_methods**](PaymentMethodsApi.md#list_payment_methods) | **GET** /payment-methods | 
[**put_branch_availability**](PaymentMethodsApi.md#put_branch_availability) | **PUT** /payment-methods/availability/branches/{branch_id} | 
[**put_device_availability**](PaymentMethodsApi.md#put_device_availability) | **PUT** /payment-methods/availability/devices/{device_id} | 
[**put_user_availability**](PaymentMethodsApi.md#put_user_availability) | **PUT** /payment-methods/availability/users/{user_id} | 
[**update_payment_method**](PaymentMethodsApi.md#update_payment_method) | **PUT** /payment-methods/{id} | 



## activate_payment_method

> models::OrgPaymentMethod activate_payment_method(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Payment Method ID | [required] |

### Return type

[**models::OrgPaymentMethod**](OrgPaymentMethod.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_payment_method

> models::OrgPaymentMethod create_payment_method(create_payment_method_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_payment_method_request** | [**CreatePaymentMethodRequest**](CreatePaymentMethodRequest.md) |  | [required] |

### Return type

[**models::OrgPaymentMethod**](OrgPaymentMethod.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## deactivate_payment_method

> models::OrgPaymentMethod deactivate_payment_method(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Payment Method ID | [required] |

### Return type

[**models::OrgPaymentMethod**](OrgPaymentMethod.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_availability

> models::PaymentMethodAvailability get_availability(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::PaymentMethodAvailability**](PaymentMethodAvailability.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_effective

> Vec<models::OrgPaymentMethod> get_effective(branch_id, user_id, device_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**user_id** | Option<**uuid::Uuid**> |  |  |
**device_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**Vec<models::OrgPaymentMethod>**](OrgPaymentMethod.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_payment_methods

> Vec<models::OrgPaymentMethod> list_payment_methods()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::OrgPaymentMethod>**](OrgPaymentMethod.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_branch_availability

> models::AllowList put_branch_availability(branch_id, allow_list)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**allow_list** | [**AllowList**](AllowList.md) |  | [required] |

### Return type

[**models::AllowList**](AllowList.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_device_availability

> models::AllowList put_device_availability(device_id, allow_list)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**device_id** | **uuid::Uuid** | Device ID | [required] |
**allow_list** | [**AllowList**](AllowList.md) |  | [required] |

### Return type

[**models::AllowList**](AllowList.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_user_availability

> models::AllowList put_user_availability(user_id, allow_list)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** | User (teller) ID | [required] |
**allow_list** | [**AllowList**](AllowList.md) |  | [required] |

### Return type

[**models::AllowList**](AllowList.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_payment_method

> models::OrgPaymentMethod update_payment_method(id, update_payment_method_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Payment Method ID | [required] |
**update_payment_method_request** | [**UpdatePaymentMethodRequest**](UpdatePaymentMethodRequest.md) |  | [required] |

### Return type

[**models::OrgPaymentMethod**](OrgPaymentMethod.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

