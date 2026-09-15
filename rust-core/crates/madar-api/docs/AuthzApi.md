# \AuthzApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_role**](AuthzApi.md#create_role) | **POST** /authz/roles | 
[**delete_role**](AuthzApi.md#delete_role) | **DELETE** /authz/roles/{id} | 
[**explain**](AuthzApi.md#explain) | **GET** /authz/explain | 
[**get_my_authz**](AuthzApi.md#get_my_authz) | **GET** /authz/me | 
[**get_policy**](AuthzApi.md#get_policy) | **GET** /authz/policy | 
[**list_roles**](AuthzApi.md#list_roles) | **GET** /authz/roles | 
[**rename_role**](AuthzApi.md#rename_role) | **PATCH** /authz/roles/{id} | 
[**set_assignments**](AuthzApi.md#set_assignments) | **PUT** /authz/users/{id}/assignments | 
[**set_override**](AuthzApi.md#set_override) | **PUT** /authz/users/{id}/overrides | 
[**set_policy**](AuthzApi.md#set_policy) | **PUT** /authz/policy | 
[**set_role_grant**](AuthzApi.md#set_role_grant) | **PUT** /authz/roles/{id}/grants | 
[**user_access**](AuthzApi.md#user_access) | **GET** /authz/users/{id} | 



## create_role

> models::RoleView create_role(create_role_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_role_request** | [**CreateRoleRequest**](CreateRoleRequest.md) |  | [required] |

### Return type

[**models::RoleView**](RoleView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_role

> delete_role(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Role ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## explain

> models::Explanation explain(user_id, capability, branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**user_id** | **uuid::Uuid** |  | [required] |
**capability** | **String** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**models::Explanation**](Explanation.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_my_authz

> models::MyAuthz get_my_authz(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**models::MyAuthz**](MyAuthz.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_policy

> Vec<models::PolicyEntry> get_policy()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::PolicyEntry>**](PolicyEntry.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_roles

> Vec<models::RoleView> list_roles()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::RoleView>**](RoleView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## rename_role

> models::RoleView rename_role(id, rename_role_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Role ID | [required] |
**rename_role_request** | [**RenameRoleRequest**](RenameRoleRequest.md) |  | [required] |

### Return type

[**models::RoleView**](RoleView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_assignments

> models::UserAccess set_assignments(id, set_assignments_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | User ID | [required] |
**set_assignments_request** | [**SetAssignmentsRequest**](SetAssignmentsRequest.md) |  | [required] |

### Return type

[**models::UserAccess**](UserAccess.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_override

> models::UserAccess set_override(id, set_override_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | User ID | [required] |
**set_override_request** | [**SetOverrideRequest**](SetOverrideRequest.md) |  | [required] |

### Return type

[**models::UserAccess**](UserAccess.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_policy

> Vec<models::PolicyEntry> set_policy(policy_entry)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**policy_entry** | [**PolicyEntry**](PolicyEntry.md) |  | [required] |

### Return type

[**Vec<models::PolicyEntry>**](PolicyEntry.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_role_grant

> models::RoleView set_role_grant(id, set_grant_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Role ID | [required] |
**set_grant_request** | [**SetGrantRequest**](SetGrantRequest.md) |  | [required] |

### Return type

[**models::RoleView**](RoleView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## user_access

> models::UserAccess user_access(id, branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | User ID | [required] |
**branch_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**models::UserAccess**](UserAccess.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

