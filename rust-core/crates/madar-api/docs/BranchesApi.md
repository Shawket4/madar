# \BranchesApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_branch**](BranchesApi.md#create_branch) | **POST** /branches | 
[**delete_branch**](BranchesApi.md#delete_branch) | **DELETE** /branches/{id} | 
[**get_branch**](BranchesApi.md#get_branch) | **GET** /branches/{id} | 
[**list_branches**](BranchesApi.md#list_branches) | **GET** /branches | 
[**list_timezones**](BranchesApi.md#list_timezones) | **GET** /timezones | The full set of selectable IANA timezones — the labels of the `timezone_name` DB enum. The dashboard's timezone `<select>` is populated from this, so the frontend can never offer a value the backend/DB would reject (single source of truth: DB enum → this endpoint → select options).
[**update_branch**](BranchesApi.md#update_branch) | **PUT** /branches/{id} | 



## create_branch

> models::Branch create_branch(create_branch_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_branch_request** | [**CreateBranchRequest**](CreateBranchRequest.md) |  | [required] |

### Return type

[**models::Branch**](Branch.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_branch

> delete_branch(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_branch

> models::Branch get_branch(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**models::Branch**](Branch.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_branches

> Vec<models::Branch> list_branches(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization whose branches to list. Must match the caller's JWT org. | [required] |

### Return type

[**Vec<models::Branch>**](Branch.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_timezones

> Vec<String> list_timezones()
The full set of selectable IANA timezones — the labels of the `timezone_name` DB enum. The dashboard's timezone `<select>` is populated from this, so the frontend can never offer a value the backend/DB would reject (single source of truth: DB enum → this endpoint → select options).

### Parameters

This endpoint does not need any parameter.

### Return type

**Vec<String>**

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_branch

> models::Branch update_branch(id, update_branch_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Branch ID | [required] |
**update_branch_request** | [**UpdateBranchRequest**](UpdateBranchRequest.md) |  | [required] |

### Return type

[**models::Branch**](Branch.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

