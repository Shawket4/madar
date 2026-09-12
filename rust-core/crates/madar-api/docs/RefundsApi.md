# \RefundsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_refund**](RefundsApi.md#create_refund) | **POST** /refunds | 
[**get_refund**](RefundsApi.md#get_refund) | **GET** /refunds/{id} | 
[**list_order_refunds**](RefundsApi.md#list_order_refunds) | **GET** /refunds/order/{order_id} | 
[**list_shift_refunds**](RefundsApi.md#list_shift_refunds) | **GET** /refunds/shift/{shift_id} | 



## create_refund

> models::RefundIssued create_refund(create_refund_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_refund_request** | [**CreateRefundRequest**](CreateRefundRequest.md) |  | [required] |

### Return type

[**models::RefundIssued**](RefundIssued.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_refund

> models::RefundFull get_refund(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Refund ID | [required] |

### Return type

[**models::RefundFull**](RefundFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_order_refunds

> models::OrderRefunds list_order_refunds(order_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**order_id** | **uuid::Uuid** | Order ID | [required] |

### Return type

[**models::OrderRefunds**](OrderRefunds.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_shift_refunds

> models::ShiftRefunds list_shift_refunds(shift_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**shift_id** | **uuid::Uuid** | Shift ID | [required] |

### Return type

[**models::ShiftRefunds**](ShiftRefunds.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

