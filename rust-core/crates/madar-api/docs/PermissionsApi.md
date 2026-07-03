# \PermissionsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**delete_user_permission**](PermissionsApi.md#delete_user_permission) | **DELETE** /permissions/user/{user_id}/{resource}/{action} | 
[**get_permission_matrix**](PermissionsApi.md#get_permission_matrix) | **GET** /permissions/matrix/{user_id} | 
[**get_role_permissions**](PermissionsApi.md#get_role_permissions) | **GET** /permissions/roles | 
[**get_user_permissions**](PermissionsApi.md#get_user_permissions) | **GET** /permissions/user/{user_id} | 
[**upsert_role_permission**](PermissionsApi.md#upsert_role_permission) | **PUT** /permissions/roles | 
[**upsert_user_permission**](PermissionsApi.md#upsert_user_permission) | **PUT** /permissions/user/{user_id} | 



## delete_user_permission

> delete_user_permission(user_id, resource, action)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** | User ID | [required] |
**resource** | **String** | Resource name (e.g. menu_items, orders) | [required] |
**action** | **String** | Action (create | read | update | delete) | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_permission_matrix

> Vec<models::PermissionMatrix> get_permission_matrix(user_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** | User ID | [required] |

### Return type

[**Vec<models::PermissionMatrix>**](PermissionMatrix.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_role_permissions

> Vec<models::RolePermission> get_role_permissions()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::RolePermission>**](RolePermission.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_user_permissions

> Vec<models::Permission> get_user_permissions(user_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** | User ID | [required] |

### Return type

[**Vec<models::Permission>**](Permission.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upsert_role_permission

> models::RolePermission upsert_role_permission(upsert_role_permission_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**upsert_role_permission_request** | [**UpsertRolePermissionRequest**](UpsertRolePermissionRequest.md) |  | [required] |

### Return type

[**models::RolePermission**](RolePermission.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upsert_user_permission

> models::Permission upsert_user_permission(user_id, upsert_permission_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** | User ID | [required] |
**upsert_permission_request** | [**UpsertPermissionRequest**](UpsertPermissionRequest.md) |  | [required] |

### Return type

[**models::Permission**](Permission.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

