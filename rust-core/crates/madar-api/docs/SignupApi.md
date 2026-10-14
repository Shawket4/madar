# \SignupApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**signup**](SignupApi.md#signup) | **POST** /public/signup | Make a shop on the Free plan.
[**signup_otp**](SignupApi.md#signup_otp) | **POST** /public/signup/otp | Send a code by WhatsApp to prove the owner's phone.



## signup

> models::SignupResponse signup(signup_request)
Make a shop on the Free plan.

400 for a wrong or expired code (or a bad field), 409 `SIGNUP_PHONE_TAKEN` / `SIGNUP_EMAIL_TAKEN` when the phone or email already owns an account (sign in instead), 429 from the per-IP governor. A code is spent only by a signup that succeeds: a duplicate email leaves it good for another try (within its five attempts).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**signup_request** | [**SignupRequest**](SignupRequest.md) |  | [required] |

### Return type

[**models::SignupResponse**](SignupResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## signup_otp

> models::SignupOtpResponse signup_otp(signup_otp_request)
Send a code by WhatsApp to prove the owner's phone.

409 `SIGNUP_PHONE_TAKEN` when a shop already owns the phone; 429 when a code went out in the last minute (`SIGNUP_OTP_COOLDOWN`) or five did in the last hour (`SIGNUP_OTP_LIMIT`); the per-IP governor answers 429 `RATE_LIMITED`.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**signup_otp_request** | [**SignupOtpRequest**](SignupOtpRequest.md) |  | [required] |

### Return type

[**models::SignupOtpResponse**](SignupOtpResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

