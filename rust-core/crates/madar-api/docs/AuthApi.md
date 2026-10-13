# \AuthApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**activate**](AuthApi.md#activate) | **POST** /auth/activate-device | 
[**device_session**](AuthApi.md#device_session) | **POST** /auth/device-session | A kitchen screen's sign-in: no person, no account (owner, 2026-10-11). The screen was activated once with a code from the dashboard's branch plan and keeps the credential activation handed it; with it, this mints the screen's session whenever the last one runs out, so the kitchen never signs in again.
[**get_my_permissions**](AuthApi.md#get_my_permissions) | **GET** /auth/permissions | 
[**login**](AuthApi.md#login) | **POST** /auth/login | 
[**me**](AuthApi.md#me) | **GET** /auth/me | 
[**resolve_branch**](AuthApi.md#resolve_branch) | **POST** /auth/resolve-branch | 



## activate

> models::ActivateDeviceResponse activate(activate_device_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**activate_device_request** | [**ActivateDeviceRequest**](ActivateDeviceRequest.md) |  | [required] |

### Return type

[**models::ActivateDeviceResponse**](ActivateDeviceResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## device_session

> models::LoginResponse device_session(x_madar_device, x_madar_device_token)
A kitchen screen's sign-in: no person, no account (owner, 2026-10-11). The screen was activated once with a code from the dashboard's branch plan and keeps the credential activation handed it; with it, this mints the screen's session whenever the last one runs out, so the kitchen never signs in again.

The gate is the device credential (`X-Madar-Device` + `X-Madar-Device-Token`, as for activation), on a live `kds` device bound to a branch. The session's subject is the screen's own principal (migration `20261011100000_kitchen_screen_principal.sql`), made here the first time: role `kitchen`, assigned to the screen's branch, so it holds exactly the kitchen role's capabilities there (`kitchen.display.read`, `kitchen.bump`) and nothing else. Same response as `/auth/login`, so a client reuses its whole sign-in path.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**x_madar_device** | **String** | The install id the device was activated as | [required] |
**x_madar_device_token** | **String** | The credential issued at activation | [required] |

### Return type

[**models::LoginResponse**](LoginResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


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

