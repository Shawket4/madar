# \AuthApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**get_my_permissions**](AuthApi.md#get_my_permissions) | **GET** /auth/permissions | 
[**login**](AuthApi.md#login) | **POST** /auth/login | 
[**me**](AuthApi.md#me) | **GET** /auth/me | 
[**resolve_branch**](AuthApi.md#resolve_branch) | **POST** /auth/resolve-branch | 



## get_my_permissions

> models::AuthPermissionsResponse get_my_permissions()


### Parameters

This endpoint does not need any parameter.

### Return type

[**models::AuthPermissionsResponse**](AuthPermissionsResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## login

> models::LoginResponse login(login_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**login_request** | [**LoginRequest**](LoginRequest.md) |  | [required] |

### Return type

[**models::LoginResponse**](LoginResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## me

> models::MeResponse me()


### Parameters

This endpoint does not need any parameter.

### Return type

[**models::MeResponse**](MeResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## resolve_branch

> models::ResolveBranchResponse resolve_branch(resolve_branch_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**resolve_branch_request** | [**ResolveBranchRequest**](ResolveBranchRequest.md) |  | [required] |

### Return type

[**models::ResolveBranchResponse**](ResolveBranchResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

