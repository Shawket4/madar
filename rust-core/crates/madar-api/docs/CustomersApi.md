# \CustomersApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_customer**](CustomersApi.md#create_customer) | **POST** /customers | 
[**erase_customer**](CustomersApi.md#erase_customer) | **POST** /customers/{id}/erase | 
[**get_customer**](CustomersApi.md#get_customer) | **GET** /customers/{id} | 
[**list_customer_addresses**](CustomersApi.md#list_customer_addresses) | **GET** /customers/{id}/addresses | 
[**list_customer_bookings**](CustomersApi.md#list_customer_bookings) | **GET** /customers/{id}/bookings | A customer's bookings, newest first. A merged id answers for its survivor, and bookings made under any id merged into it are included.
[**list_customers**](CustomersApi.md#list_customers) | **GET** /customers | 
[**merge_customer**](CustomersApi.md#merge_customer) | **POST** /customers/{id}/merge | 
[**update_customer**](CustomersApi.md#update_customer) | **PATCH** /customers/{id} | 



## create_customer

> models::CustomerDetail create_customer(create_customer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_customer_request** | [**CreateCustomerRequest**](CreateCustomerRequest.md) |  | [required] |

### Return type

[**models::CustomerDetail**](CustomerDetail.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## erase_customer

> erase_customer(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Customer id | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_customer

> models::CustomerDetail get_customer(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Customer id (a merged id resolves) | [required] |

### Return type

[**models::CustomerDetail**](CustomerDetail.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_customer_addresses

> Vec<models::CustomerAddress> list_customer_addresses(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Customer id (a merged id resolves) | [required] |

### Return type

[**Vec<models::CustomerAddress>**](CustomerAddress.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_customer_bookings

> Vec<models::BookingView> list_customer_bookings(id, limit, offset)
A customer's bookings, newest first. A merged id answers for its survivor, and bookings made under any id merged into it are included.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Customer ID (a merged id resolves) | [required] |
**limit** | Option<**i64**> | Default 50, at most 200. |  |
**offset** | Option<**i64**> |  |  |

### Return type

[**Vec<models::BookingView>**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_customers

> Vec<models::Customer> list_customers(q, member, source, limit, offset)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**q** | Option<**String**> | Matches name (contains) or phone (digits). |  |
**member** | Option<**bool**> | `true` = loyalty members only, `false` = non-members only. |  |
**source** | Option<**String**> | Only customers that first came from this source (`pos`, `online`, `loyalty`, `booking`, `table_qr`, `aggregator`, `dashboard`). |  |
**limit** | Option<**i64**> | Default 100, at most 500. |  |
**offset** | Option<**i64**> |  |  |

### Return type

[**Vec<models::Customer>**](Customer.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## merge_customer

> models::CustomerDetail merge_customer(id, merge_customer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | The duplicate, which stops being listed | [required] |
**merge_customer_request** | [**MergeCustomerRequest**](MergeCustomerRequest.md) |  | [required] |

### Return type

[**models::CustomerDetail**](CustomerDetail.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_customer

> models::CustomerDetail update_customer(id, update_customer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Customer id | [required] |
**update_customer_request** | [**UpdateCustomerRequest**](UpdateCustomerRequest.md) |  | [required] |

### Return type

[**models::CustomerDetail**](CustomerDetail.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

