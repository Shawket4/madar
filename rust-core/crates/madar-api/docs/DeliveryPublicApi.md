# \DeliveryPublicApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_delivery_order**](DeliveryPublicApi.md#create_delivery_order) | **POST** /public/delivery-orders | Place an online order (delivery or pickup) at a branch.
[**delivery_quote**](DeliveryPublicApi.md#delivery_quote) | **GET** /public/branches/{id}/delivery-quote | The delivery fee and zone for a point, before ordering.
[**guest_order_history**](DeliveryPublicApi.md#guest_order_history) | **GET** /public/delivery-orders/history | A customer's past orders at a shop, by their verified phone.
[**guest_past_locations**](DeliveryPublicApi.md#guest_past_locations) | **GET** /public/delivery-orders/past-locations | A customer's saved delivery addresses at a shop, by their verified phone.
[**otp_request**](DeliveryPublicApi.md#otp_request) | **POST** /public/otp/request | Send a 4-digit code by WhatsApp to verify a phone number.
[**otp_verify**](DeliveryPublicApi.md#otp_verify) | **POST** /public/otp/verify | Check a WhatsApp code and get a `device_token` that proves the phone.
[**public_branches**](DeliveryPublicApi.md#public_branches) | **GET** /public/branches | A shop's branches that take online orders, with each channel's hours and settings.
[**public_menu**](DeliveryPublicApi.md#public_menu) | **GET** /public/branches/{id}/menu | A branch's menu for one ordering channel, with prices in piastres.
[**track_delivery_order**](DeliveryPublicApi.md#track_delivery_order) | **GET** /public/delivery-orders/{id}/track | An online order's status, timeline and totals, from the id in its tracking link.



## create_delivery_order

> models::DeliveryOrder create_delivery_order(delivery_order_input)
Place an online order (delivery or pickup) at a branch.

Answers 201 with the order; follow it at `/public/delivery-orders/{id}/track`. The server prices the cart in piastres. Where the branch requires a verified phone (the default), send the `device_token` from `/public/otp/verify`.

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


## delivery_quote

> models::QuoteResponse delivery_quote(lat, lng, channel, id)
The delivery fee and zone for a point, before ordering.

Needs `lat`, `lng` and `channel`. `status` says whether the branch delivers there; the fee is in piastres.

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
A customer's past orders at a shop, by their verified phone.

Needs `phone` and the `device_token` from `/public/otp/verify`; a phone number alone unlocks nothing.

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
A customer's saved delivery addresses at a shop, by their verified phone.

Needs `phone` and the `device_token` from `/public/otp/verify`.

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


## otp_request

> models::OtpRequestResponse otp_request(otp_request_input)
Send a 4-digit code by WhatsApp to verify a phone number.

One live code per phone per minute (409 otherwise). Check it with `/public/otp/verify`.

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
Check a WhatsApp code and get a `device_token` that proves the phone.

Ordering, booking, the rewards card and order history take this token where a shop asks for a verified phone. A code allows five tries.

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

> Vec<models::PublicBranch> public_branches(org_id, browse)
A shop's branches that take online orders, with each channel's hours and settings.

`org_id` names the shop. With `browse=true` every active branch is listed, for a read-only menu.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**browse** | Option<**bool**> | The read-only menu (`/menu`): every active branch, not only the ones taking online orders — a shop with ordering switched off still has a menu to show. Each branch's channel flags stay as they are, so a client never offers an order where none is taken. |  |

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
A branch's menu for one ordering channel, with prices in piastres.

`channel` is `in_mall`, `outside`, `umbrella` or `pickup`. `preview=true` shows a channel's menu while it is closed, and `channel=dine_in&preview=true` gives the read-only dine-in menu. Nothing can be ordered from a preview.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**channel** | **String** | A delivery channel, or `dine_in` — the dine-in menu (branch prices, no channel discount), accepted ONLY with `preview=true`: the read-only menu of a shop that takes no online orders. Nothing can be ordered against it; quote and intake know no such channel. | [required] |
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
An online order's status, timeline and totals, from the id in its tracking link.

Amounts are in piastres.

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

