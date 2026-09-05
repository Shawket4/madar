# \BookingsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**booking_availability**](BookingsApi.md#booking_availability) | **GET** /bookings/availability | 
[**booking_stats**](BookingsApi.md#booking_stats) | **GET** /bookings/stats | 
[**cancel_booking**](BookingsApi.md#cancel_booking) | **POST** /bookings/{id}/cancel | 
[**complete_booking**](BookingsApi.md#complete_booking) | **POST** /bookings/{id}/complete | 
[**create_booking**](BookingsApi.md#create_booking) | **POST** /bookings | 
[**get_booking**](BookingsApi.md#get_booking) | **GET** /bookings/{id} | 
[**get_booking_settings**](BookingsApi.md#get_booking_settings) | **GET** /bookings/settings | 
[**list_bookings**](BookingsApi.md#list_bookings) | **GET** /bookings | 
[**no_show_booking**](BookingsApi.md#no_show_booking) | **POST** /bookings/{id}/no-show | 
[**put_booking_settings**](BookingsApi.md#put_booking_settings) | **PUT** /bookings/settings | 
[**seat_booking**](BookingsApi.md#seat_booking) | **POST** /bookings/{id}/seat | 
[**update_booking**](BookingsApi.md#update_booking) | **PATCH** /bookings/{id} | 



## booking_availability

> models::AvailabilityResponse booking_availability(branch_id, date, party_size, section_id, exclude_booking_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**date** | **String** |  | [required] |
**party_size** | **i32** |  | [required] |
**section_id** | Option<**uuid::Uuid**> |  |  |
**exclude_booking_id** | Option<**uuid::Uuid**> | Ignore this booking's own claims (when moving it). |  |

### Return type

[**models::AvailabilityResponse**](AvailabilityResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## booking_stats

> models::BookingStats booking_stats(branch_id, from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | **chrono::DateTime<chrono::FixedOffset>** |  | [required] |
**to** | **chrono::DateTime<chrono::FixedOffset>** |  | [required] |

### Return type

[**models::BookingStats**](BookingStats.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## cancel_booking

> models::BookingView cancel_booking(id, cancel_booking_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Booking ID | [required] |
**cancel_booking_request** | [**CancelBookingRequest**](CancelBookingRequest.md) |  | [required] |

### Return type

[**models::BookingView**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## complete_booking

> models::BookingView complete_booking(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Booking ID | [required] |

### Return type

[**models::BookingView**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_booking

> models::BookingView create_booking(create_booking_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_booking_request** | [**CreateBookingRequest**](CreateBookingRequest.md) |  | [required] |

### Return type

[**models::BookingView**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_booking

> models::BookingView get_booking(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Booking ID | [required] |

### Return type

[**models::BookingView**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_booking_settings

> models::BookingSettings get_booking_settings(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::BookingSettings**](BookingSettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_bookings

> Vec<models::BookingView> list_bookings(branch_id, date, from, to, active, status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**date** | Option<**String**> | Service date (`YYYY-MM-DD`, branch-local, 05:00→05:00). Defaults to today. |  |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Explicit window (overrides `date`). |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**active** | Option<**bool**> | Only `confirmed` / `seated`. |  |
**status** | Option<**String**> |  |  |

### Return type

[**Vec<models::BookingView>**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## no_show_booking

> models::BookingView no_show_booking(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Booking ID | [required] |

### Return type

[**models::BookingView**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_booking_settings

> models::BookingSettings put_booking_settings(booking_settings)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**booking_settings** | [**BookingSettings**](BookingSettings.md) |  | [required] |

### Return type

[**models::BookingSettings**](BookingSettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## seat_booking

> models::BookingView seat_booking(id, seat_booking_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Booking ID | [required] |
**seat_booking_request** | [**SeatBookingRequest**](SeatBookingRequest.md) |  | [required] |

### Return type

[**models::BookingView**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_booking

> models::BookingView update_booking(id, update_booking_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Booking ID | [required] |
**update_booking_request** | [**UpdateBookingRequest**](UpdateBookingRequest.md) |  | [required] |

### Return type

[**models::BookingView**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

