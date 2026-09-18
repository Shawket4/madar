# \AuthzApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**authz_keys**](AuthzApi.md#authz_keys) | **GET** /auth/authz-keys | 
[**bulk_review_flags**](AuthzApi.md#bulk_review_flags) | **POST** /authz/flags/bulk-review | Resolve many flags at once — \"select many\" or \"everything for this till or day\" from the dashboard's review queue (owner, 2026-09-17). Extends [`review_flag`] rather than duplicating it: same capability, same semantics (an acknowledgement, not an approval), now with an optional note and one id at a time so a bad id among many never loses the rest.
[**create_role**](AuthzApi.md#create_role) | **POST** /authz/roles | 
[**delete_role**](AuthzApi.md#delete_role) | **DELETE** /authz/roles/{id} | 
[**explain**](AuthzApi.md#explain) | **GET** /authz/explain | 
[**get_my_authz**](AuthzApi.md#get_my_authz) | **GET** /authz/me | 
[**get_policy**](AuthzApi.md#get_policy) | **GET** /authz/policy | 
[**list_flags**](AuthzApi.md#list_flags) | **GET** /authz/flags | 
[**list_roles**](AuthzApi.md#list_roles) | **GET** /authz/roles | 
[**rename_role**](AuthzApi.md#rename_role) | **PATCH** /authz/roles/{id} | 
[**review_flag**](AuthzApi.md#review_flag) | **POST** /authz/flags/{id}/review | Mark one flag as looked at. It is an acknowledgement, not an approval: the act is already on the books either way, so there is nothing here to undo or let through.
[**set_assignments**](AuthzApi.md#set_assignments) | **PUT** /authz/users/{id}/assignments | 
[**set_override**](AuthzApi.md#set_override) | **PUT** /authz/users/{id}/overrides | 
[**set_policy**](AuthzApi.md#set_policy) | **PUT** /authz/policy | 
[**set_role_grant**](AuthzApi.md#set_role_grant) | **PUT** /authz/roles/{id}/grants | 
[**user_access**](AuthzApi.md#user_access) | **GET** /authz/users/{id} | 



## authz_keys

> Vec<models::AuthzPublicKey> authz_keys()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::AuthzPublicKey>**](AuthzPublicKey.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## bulk_review_flags

> models::BulkReviewResult bulk_review_flags(bulk_review_request)
Resolve many flags at once — \"select many\" or \"everything for this till or day\" from the dashboard's review queue (owner, 2026-09-17). Extends [`review_flag`] rather than duplicating it: same capability, same semantics (an acknowledgement, not an approval), now with an optional note and one id at a time so a bad id among many never loses the rest.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**bulk_review_request** | [**BulkReviewRequest**](BulkReviewRequest.md) |  | [required] |

### Return type

[**models::BulkReviewResult**](BulkReviewResult.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


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


## list_flags

> Vec<models::ReplayFlag> list_flags(include_reviewed, approval)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**include_reviewed** | Option<**bool**> | Include flags already reviewed. Default false: the queue is what is left to look at. |  |
**approval** | Option<**String**> | Optional one-time manager approval, the ordinary `ReplayApproval` shape JSON-encoded (a GET has no body). A till signed in as a TELLER uses it to pull its own branch's flags with a manager's PIN; leaving it out is exactly the old behaviour, `approvals.review` on the bearer. |  |

### Return type

[**Vec<models::ReplayFlag>**](ReplayFlag.md)

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


## review_flag

> models::ReplayFlag review_flag(id)
Mark one flag as looked at. It is an acknowledgement, not an approval: the act is already on the books either way, so there is nothing here to undo or let through.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **i64** |  | [required] |

### Return type

[**models::ReplayFlag**](ReplayFlag.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
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

