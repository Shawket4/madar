# \AdminApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**get_session**](AdminApi.md#get_session) | **GET** /admin/sessions/{id} | One session.
[**list_sessions**](AdminApi.md#list_sessions) | **GET** /admin/sessions | List sessions, newest first.
[**revoke_org_sessions**](AdminApi.md#revoke_org_sessions) | **POST** /admin/orgs/{id}/revoke-sessions | Sign out a whole org, or only its sessions of some kinds.
[**revoke_session**](AdminApi.md#revoke_session) | **POST** /admin/sessions/{id}/revoke | Revoke one session: its next request is refused (401 `SESSION_REVOKED`).
[**revoke_user_sessions**](AdminApi.md#revoke_user_sessions) | **POST** /admin/users/{id}/revoke-sessions | Sign a person out everywhere, including tokens of theirs from before sessions existed.



## get_session

> models::SessionRow get_session(id)
One session.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Session id | [required] |

### Return type

[**models::SessionRow**](SessionRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_sessions

> models::SessionPage list_sessions(org_id, user_id, branch_id, kind, q, state, limit, before, before_id)
List sessions, newest first.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | Option<**uuid::Uuid**> |  |  |
**user_id** | Option<**uuid::Uuid**> |  |  |
**branch_id** | Option<**uuid::Uuid**> |  |  |
**kind** | Option<**String**> | `password` | `pin` | `device` | `signup` | `demo` | `legacy`. |  |
**q** | Option<**String**> | Matches the person's name or email, the device id or the IP. |  |
**state** | Option<**String**> | `active` (default) | `revoked` | `expired` | `all`. |  |
**limit** | Option<**i64**> |  |  |
**before** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Keyset cursor: the `next` of the previous page. |  |
**before_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**models::SessionPage**](SessionPage.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## revoke_org_sessions

> models::RevokeResponse revoke_org_sessions(id, revoke_org_request)
Sign out a whole org, or only its sessions of some kinds.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Organization id | [required] |
**revoke_org_request** | [**RevokeOrgRequest**](RevokeOrgRequest.md) |  | [required] |

### Return type

[**models::RevokeResponse**](RevokeResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## revoke_session

> models::RevokeResponse revoke_session(id, revoke_request)
Revoke one session: its next request is refused (401 `SESSION_REVOKED`).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Session id | [required] |
**revoke_request** | [**RevokeRequest**](RevokeRequest.md) |  | [required] |

### Return type

[**models::RevokeResponse**](RevokeResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## revoke_user_sessions

> models::RevokeResponse revoke_user_sessions(id, revoke_request)
Sign a person out everywhere, including tokens of theirs from before sessions existed.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | User id | [required] |
**revoke_request** | [**RevokeRequest**](RevokeRequest.md) |  | [required] |

### Return type

[**models::RevokeResponse**](RevokeResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

