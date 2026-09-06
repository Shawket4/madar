# \BookingsPublicApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**booking_branches**](BookingsPublicApi.md#booking_branches) | **GET** /public/booking-branches | 
[**booking_info**](BookingsPublicApi.md#booking_info) | **GET** /public/branches/{id}/booking-info | 
[**booking_slots**](BookingsPublicApi.md#booking_slots) | **GET** /public/branches/{id}/booking-slots | 
[**cancel_public_booking**](BookingsPublicApi.md#cancel_public_booking) | **POST** /public/bookings/{token}/cancel | 
[**create_public_booking**](BookingsPublicApi.md#create_public_booking) | **POST** /public/bookings | 
[**get_public_booking**](BookingsPublicApi.md#get_public_booking) | **GET** /public/bookings/{token} | 
[**update_public_booking**](BookingsPublicApi.md#update_public_booking) | **PATCH** /public/bookings/{token} | 



## booking_branches

> Vec<models::PublicBookingBranch> booking_branches(org_id)


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

