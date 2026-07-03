# \StocktakesApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancel_stocktake**](StocktakesApi.md#cancel_stocktake) | **POST** /stocktakes/{id}/cancel | 
[**create_stocktake**](StocktakesApi.md#create_stocktake) | **POST** /stocktakes/branches/{branch_id} | 
[**finalize_stocktake**](StocktakesApi.md#finalize_stocktake) | **POST** /stocktakes/{id}/finalize | 
[**get_stocktake**](StocktakesApi.md#get_stocktake) | **GET** /stocktakes/{id} | 
[**list_stocktakes**](StocktakesApi.md#list_stocktakes) | **GET** /stocktakes/branches/{branch_id} | 
[**upsert_items**](StocktakesApi.md#upsert_items) | **PUT** /stocktakes/{id}/items | 
[**variance_report**](StocktakesApi.md#variance_report) | **GET** /stocktakes/{id}/variance-report | 



## cancel_stocktake

> models::Stocktake cancel_stocktake(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Stocktake ID | [required] |

### Return type

[**models::Stocktake**](Stocktake.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_stocktake

> models::StocktakeFull create_stocktake(branch_id, create_stocktake_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**create_stocktake_request** | [**CreateStocktakeRequest**](CreateStocktakeRequest.md) |  | [required] |

### Return type

[**models::StocktakeFull**](StocktakeFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## finalize_stocktake

> models::StocktakeFull finalize_stocktake(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Stocktake ID | [required] |

### Return type

[**models::StocktakeFull**](StocktakeFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_stocktake

> models::StocktakeFull get_stocktake(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Stocktake ID | [required] |

### Return type

[**models::StocktakeFull**](StocktakeFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_stocktakes

> Vec<models::Stocktake> list_stocktakes(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**Vec<models::Stocktake>**](Stocktake.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upsert_items

> models::StocktakeFull upsert_items(id, upsert_items_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Stocktake ID | [required] |
**upsert_items_request** | [**UpsertItemsRequest**](UpsertItemsRequest.md) |  | [required] |

### Return type

[**models::StocktakeFull**](StocktakeFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## variance_report

> models::VarianceReport variance_report(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Stocktake ID | [required] |

### Return type

[**models::VarianceReport**](VarianceReport.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

