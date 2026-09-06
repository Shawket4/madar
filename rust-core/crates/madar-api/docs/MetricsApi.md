# \MetricsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**run_metrics_query**](MetricsApi.md#run_metrics_query) | **POST** /metrics/query | 
[**schema**](MetricsApi.md#schema) | **GET** /metrics/schema | 



## run_metrics_query

> models::MetricsQueryResponse run_metrics_query(metrics_query_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**metrics_query_request** | [**MetricsQueryRequest**](MetricsQueryRequest.md) |  | [required] |

### Return type

[**models::MetricsQueryResponse**](MetricsQueryResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## schema

> models::RegistryInfo schema()


### Parameters

This endpoint does not need any parameter.

### Return type

[**models::RegistryInfo**](RegistryInfo.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

