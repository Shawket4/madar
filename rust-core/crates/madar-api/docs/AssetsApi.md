# \AssetsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**get_asset_bundle**](AssetsApi.md#get_asset_bundle) | **GET** /sync/asset-bundles/{org_id}/{file_name} | 
[**get_job**](AssetsApi.md#get_job) | **GET** /assets/jobs/{id} | 
[**top_up**](AssetsApi.md#top_up) | **POST** /sync/assets | 



## get_asset_bundle

> get_asset_bundle(org_id, file_name)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**file_name** | **String** | assets-<branch_id>-<seq>.tar | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_job

> models::AssetJobView get_job(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Asset job id | [required] |

### Return type

[**models::AssetJobView**](AssetJobView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## top_up

> top_up(top_up_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**top_up_request** | [**TopUpRequest**](TopUpRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

