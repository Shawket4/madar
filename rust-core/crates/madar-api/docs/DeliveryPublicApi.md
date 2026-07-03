# \DeliveryPublicApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_delivery_order**](DeliveryPublicApi.md#create_delivery_order) | **POST** /public/delivery-orders | 
[**create_public_booking**](DeliveryPublicApi.md#create_public_booking) | **POST** /public/reservations | 
[**delivery_quote**](DeliveryPublicApi.md#delivery_quote) | **GET** /public/branches/{id}/delivery-quote | 
[**guest_order_history**](DeliveryPublicApi.md#guest_order_history) | **GET** /public/delivery-orders/history | 
[**guest_past_locations**](DeliveryPublicApi.md#guest_past_locations) | **GET** /public/delivery-orders/past-locations | 
[**list_reservation_public_branches**](DeliveryPublicApi.md#list_reservation_public_branches) | **GET** /public/reservations/branches | 
[**otp_request**](DeliveryPublicApi.md#otp_request) | **POST** /public/otp/request | 
[**otp_verify**](DeliveryPublicApi.md#otp_verify) | **POST** /public/otp/verify | 
[**public_branches**](DeliveryPublicApi.md#public_branches) | **GET** /public/branches | 
[**public_menu**](DeliveryPublicApi.md#public_menu) | **GET** /public/branches/{id}/menu | 
[**track_delivery_order**](DeliveryPublicApi.md#track_delivery_order) | **GET** /public/delivery-orders/{id}/track | 
[**track_public_booking**](DeliveryPublicApi.md#track_public_booking) | **GET** /public/reservations/{id} | 



## create_delivery_order

> models::DeliveryOrder create_delivery_order(delivery_order_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**delivery_order_input** | [**DeliveryOrderInput**](DeliveryOrderInput.md) |  | [required] |

### Return type

[**models::DeliveryOrder**](DeliveryOrder.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_public_booking

> models::PublicBooking create_public_booking(public_create_booking_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**public_create_booking_request** | [**PublicCreateBookingRequest**](PublicCreateBookingRequest.md) |  | [required] |

### Return type

[**models::PublicBooking**](PublicBooking.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delivery_quote

> models::QuoteResponse delivery_quote(lat, lng, channel, id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**lat** | **f64** |  | [required] |
**lng** | **f64** |  | [required] |
**channel** | **String** |  | [required] |
**id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::QuoteResponse**](QuoteResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## guest_order_history

> Vec<models::OrderHistorySummary> guest_order_history(phone, org_id, device_token)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**phone** | **String** |  | [required] |
**org_id** | **uuid::Uuid** |  | [required] |
**device_token** | Option<**String**> |  |  |

### Return type

[**Vec<models::OrderHistorySummary>**](OrderHistorySummary.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## guest_past_locations

> Vec<models::GuestSavedLocation> guest_past_locations(phone, org_id, branch_id, device_token)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**phone** | **String** |  | [required] |
**org_id** | **uuid::Uuid** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> |  |  |
**device_token** | Option<**String**> |  |  |

### Return type

[**Vec<models::GuestSavedLocation>**](GuestSavedLocation.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_reservation_public_branches

> Vec<models::PublicBranch> list_reservation_public_branches(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::PublicBranch>**](PublicBranch.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## otp_request

> models::OtpRequestResponse otp_request(otp_request_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**otp_request_input** | [**OtpRequestInput**](OtpRequestInput.md) |  | [required] |

### Return type

[**models::OtpRequestResponse**](OtpRequestResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## otp_verify

> models::OtpVerifyResponse otp_verify(otp_verify_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**otp_verify_input** | [**OtpVerifyInput**](OtpVerifyInput.md) |  | [required] |

### Return type

[**models::OtpVerifyResponse**](OtpVerifyResponse.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## public_branches

> Vec<models::PublicBranch> public_branches(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::PublicBranch>**](PublicBranch.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## public_menu

> models::DeliveryMenu public_menu(channel, id, preview)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**channel** | **String** |  | [required] |
**id** | **uuid::Uuid** |  | [required] |
**preview** | Option<**bool**> | Read-only browse preview. When `true`, the menu is returned even if the channel is closed right now, so customers can browse while a branch is closed. This NEVER relaxes the channel-*enabled* check, and the delivery-quote / order-intake endpoints stay gated on open-now — so a preview can never become a real order against a closed channel. |  |

### Return type

[**models::DeliveryMenu**](DeliveryMenu.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## track_delivery_order

> models::DeliveryTracking track_delivery_order(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::DeliveryTracking**](DeliveryTracking.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## track_public_booking

> models::PublicBooking track_public_booking(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Booking ID | [required] |

### Return type

[**models::PublicBooking**](PublicBooking.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

