# \BundlesApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**activate_bundle**](BundlesApi.md#activate_bundle) | **POST** /bundles/{id}/activate | 
[**archive_bundle**](BundlesApi.md#archive_bundle) | **POST** /bundles/{id}/archive | 
[**available_bundles**](BundlesApi.md#available_bundles) | **GET** /bundles/available | 
[**bundle_performance**](BundlesApi.md#bundle_performance) | **GET** /bundles/{id}/performance | 
[**create_bundle**](BundlesApi.md#create_bundle) | **POST** /bundles | 
[**delete_bundle**](BundlesApi.md#delete_bundle) | **DELETE** /bundles/{id} | 
[**get_bundle**](BundlesApi.md#get_bundle) | **GET** /bundles/{id} | 
[**list_bundles**](BundlesApi.md#list_bundles) | **GET** /bundles | 
[**suggested_components**](BundlesApi.md#suggested_components) | **GET** /bundles/suggested-components | Suggest menu items frequently ordered alongside the given item set, to help a manager pick the next component while building a bundle. Anchors on whichever items are already added: an item is suggested if it co-occurred, on the same order, with at least one anchor item at least `min_count` times across the org's branches in the given window.
[**update_bundle**](BundlesApi.md#update_bundle) | **PATCH** /bundles/{id} | 



## activate_bundle

> models::BundleWithComponents activate_bundle(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Bundle ID | [required] |

### Return type

[**models::BundleWithComponents**](BundleWithComponents.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## archive_bundle

> models::BundleWithComponents archive_bundle(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Bundle ID | [required] |

### Return type

[**models::BundleWithComponents**](BundleWithComponents.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## available_bundles

> Vec<models::BundleWithComponents> available_bundles(branch_id, at)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |

### Return type

[**Vec<models::BundleWithComponents>**](BundleWithComponents.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## bundle_performance

> models::BundlePerformanceResponse bundle_performance(id, start_date, end_date)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**start_date** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**end_date** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |

### Return type

[**models::BundlePerformanceResponse**](BundlePerformanceResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_bundle

> models::BundleWithComponents create_bundle(create_bundle_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_bundle_request** | [**CreateBundleRequest**](CreateBundleRequest.md) |  | [required] |

### Return type

[**models::BundleWithComponents**](BundleWithComponents.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_bundle

> delete_bundle(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Bundle ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_bundle

> models::BundleWithComponents get_bundle(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Bundle ID | [required] |

### Return type

[**models::BundleWithComponents**](BundleWithComponents.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_bundles

> models::PaginatedBundles list_bundles(org_id, status, branch_id, search, page, per_page, sort)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | Option<**uuid::Uuid**> |  |  |
**status** | Option<[**BundleStatus**](BundleStatus.md)> |  |  |
**branch_id** | Option<**uuid::Uuid**> |  |  |
**search** | Option<**String**> |  |  |
**page** | Option<**i64**> |  |  |
**per_page** | Option<**i64**> |  |  |
**sort** | Option<**String**> | Sort: name_asc | name_desc | price_asc | price_desc | created_asc | created_desc (default). |  |

### Return type

[**models::PaginatedBundles**](PaginatedBundles.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## suggested_components

> Vec<models::SuggestedComponent> suggested_components(org_id, item_ids, start_date, end_date, limit, min_count)
Suggest menu items frequently ordered alongside the given item set, to help a manager pick the next component while building a bundle. Anchors on whichever items are already added: an item is suggested if it co-occurred, on the same order, with at least one anchor item at least `min_count` times across the org's branches in the given window.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**item_ids** | **String** | Comma-separated menu item IDs already added to the in-progress bundle. | [required] |
**start_date** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**end_date** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> | Max suggestions to return. Default 10. |  |
**min_count** | Option<**i64**> | Minimum number of orders an item must co-occur with the anchor set in to be suggested. Default 3. |  |

### Return type

[**Vec<models::SuggestedComponent>**](SuggestedComponent.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_bundle

> models::BundleWithComponents update_bundle(id, update_bundle_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Bundle ID | [required] |
**update_bundle_request** | [**UpdateBundleRequest**](UpdateBundleRequest.md) |  | [required] |

### Return type

[**models::BundleWithComponents**](BundleWithComponents.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

