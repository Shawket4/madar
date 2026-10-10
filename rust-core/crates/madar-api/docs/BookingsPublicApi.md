# \BookingsPublicApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**booking_branches**](BookingsPublicApi.md#booking_branches) | **GET** /public/booking-branches | A shop's branches that take table bookings online.
[**booking_info**](BookingsPublicApi.md#booking_info) | **GET** /public/branches/{id}/booking-info | A branch's booking rules: party sizes, slot length, lead time and how far ahead.
[**booking_slots**](BookingsPublicApi.md#booking_slots) | **GET** /public/branches/{id}/booking-slots | The free booking times at a branch for one date and party size.
[**cancel_public_booking**](BookingsPublicApi.md#cancel_public_booking) | **POST** /public/bookings/{token}/cancel | Cancel a booking, by its manage token.
[**create_public_booking**](BookingsPublicApi.md#create_public_booking) | **POST** /public/bookings | Book a table at a branch.
[**get_public_booking**](BookingsPublicApi.md#get_public_booking) | **GET** /public/bookings/{token} | A booking, by the manage token from its confirmation link.
[**update_public_booking**](BookingsPublicApi.md#update_public_booking) | **PATCH** /public/bookings/{token} | Change a booking's time, party size or notes, by its manage token.



## booking_branches

> Vec<models::PublicBookingBranch> booking_branches(org_id)
A shop's branches that take table bookings online.

`org_id` names the shop. Only active branches with booking switched on are listed.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::PublicBookingBranch>**](PublicBookingBranch.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## booking_info

> models::PublicBookingInfo booking_info(id)
A branch's booking rules: party sizes, slot length, lead time and how far ahead.

`require_otp` says whether a booking needs a phone verified through `/public/otp/verify`.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**models::PublicBookingInfo**](PublicBookingInfo.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## booking_slots

> models::PublicSlots booking_slots(id, date, party_size)
The free booking times at a branch for one date and party size.

Refused when the branch takes no online bookings, or the date or party size is outside its rules.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Branch ID | [required] |
**date** | **String** |  | [required] |
**party_size** | **i32** |  | [required] |

### Return type

[**models::PublicSlots**](PublicSlots.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## cancel_public_booking

> models::PublicBookingView cancel_public_booking(token)
Cancel a booking, by its manage token.

Cancelling a booking that is already cancelled returns it unchanged. A party already seated is the venue's to cancel.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**token** | **String** | Manage token | [required] |

### Return type

[**models::PublicBookingView**](PublicBookingView.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_public_booking

> models::PublicBookingView create_public_booking(public_booking_input)
Book a table at a branch.

Answers 201 with the booking. The time must be a free slot after the branch's lead time. Where the branch's `require_otp` is on, send the `device_token` from `/public/otp/verify`.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**public_booking_input** | [**PublicBookingInput**](PublicBookingInput.md) |  | [required] |

### Return type

[**models::PublicBookingView**](PublicBookingView.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_public_booking

> models::PublicBookingView get_public_booking(token)
A booking, by the manage token from its confirmation link.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**token** | **String** | Manage token from the confirmation link | [required] |

### Return type

[**models::PublicBookingView**](PublicBookingView.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_public_booking

> models::PublicBookingView update_public_booking(token, public_booking_change)
Change a booking's time, party size or notes, by its manage token.

Only a confirmed booking, and only until the branch's lead time before it starts; after that, 409.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**token** | **String** | Manage token | [required] |
**public_booking_change** | [**PublicBookingChange**](PublicBookingChange.md) |  | [required] |

### Return type

[**models::PublicBookingView**](PublicBookingView.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

