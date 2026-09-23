# \StaffAuthApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**staff_otp_request**](StaffAuthApi.md#staff_otp_request) | **POST** /auth/staff/otp/request | 
[**staff_otp_verify**](StaffAuthApi.md#staff_otp_verify) | **POST** /auth/staff/otp/verify | 
[**staff_token_refresh**](StaffAuthApi.md#staff_token_refresh) | **POST** /auth/staff/refresh | A fresh staff token for the phone that sends its device token in `X-Staff-Device` (RO-3). The device is the refresh credential: once it is revoked (a new phone, a new number, the employee deactivated) this answers 401 `DEVICE_REVOKED` and the app signs out. The same checks as every `/staff/_*` call: the employee is active with app access, the business is active and has Dawam on.



## staff_otp_request

> models::StaffOtpSent staff_otp_request(staff_otp_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**staff_otp_request** | [**StaffOtpRequest**](StaffOtpRequest.md) |  | [required] |

### Return type

[**models::StaffOtpSent**](StaffOtpSent.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## staff_otp_verify

> models::StaffSession staff_otp_verify(staff_otp_verify)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**staff_otp_verify** | [**StaffOtpVerify**](StaffOtpVerify.md) |  | [required] |

### Return type

[**models::StaffSession**](StaffSession.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## staff_token_refresh

> models::StaffTokenRefresh staff_token_refresh(x_staff_device)
A fresh staff token for the phone that sends its device token in `X-Staff-Device` (RO-3). The device is the refresh credential: once it is revoked (a new phone, a new number, the employee deactivated) this answers 401 `DEVICE_REVOKED` and the app signs out. The same checks as every `/staff/_*` call: the employee is active with app access, the business is active and has Dawam on.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**x_staff_device** | **String** | The device token from sign-in | [required] |

### Return type

[**models::StaffTokenRefresh**](StaffTokenRefresh.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

