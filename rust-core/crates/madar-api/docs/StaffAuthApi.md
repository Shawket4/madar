# \StaffAuthApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**staff_otp_request**](StaffAuthApi.md#staff_otp_request) | **POST** /auth/staff/otp/request | 
[**staff_otp_verify**](StaffAuthApi.md#staff_otp_verify) | **POST** /auth/staff/otp/verify | 



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

