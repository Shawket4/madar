# \WhatsappApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**whatsapp_logout**](WhatsappApi.md#whatsapp_logout) | **POST** /whatsapp/logout | Unlink the current number. Idempotent — logging out an already-unlinked session still returns the (now logged-out) status.
[**whatsapp_pair**](WhatsappApi.md#whatsapp_pair) | **POST** /whatsapp/pair | Start (or restart) pairing on the gateway. The QR becomes available a moment later — the dashboard polls `GET /whatsapp/status` until `has_qr`, shows it, then keeps polling until `logged_in`.
[**whatsapp_pause**](WhatsappApi.md#whatsapp_pause) | **POST** /whatsapp/pause | Pause or resume all outbound WhatsApp sends. Persisted; survives restarts and does not touch the linked session.
[**whatsapp_status**](WhatsappApi.md#whatsapp_status) | **GET** /whatsapp/status | Current WhatsApp link + pause status, with the pairing QR inlined when one is waiting to be scanned. Safe to poll from the dashboard.



## whatsapp_logout

> models::WhatsappStatus whatsapp_logout()
Unlink the current number. Idempotent — logging out an already-unlinked session still returns the (now logged-out) status.

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::WhatsappStatus**](WhatsappStatus.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## whatsapp_pair

> models::WhatsappStatus whatsapp_pair()
Start (or restart) pairing on the gateway. The QR becomes available a moment later — the dashboard polls `GET /whatsapp/status` until `has_qr`, shows it, then keeps polling until `logged_in`.

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::WhatsappStatus**](WhatsappStatus.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## whatsapp_pause

> models::WhatsappStatus whatsapp_pause(pause_input)
Pause or resume all outbound WhatsApp sends. Persisted; survives restarts and does not touch the linked session.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**pause_input** | [**PauseInput**](PauseInput.md) |  | [required] |

### Return type

[**models::WhatsappStatus**](WhatsappStatus.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## whatsapp_status

> models::WhatsappStatus whatsapp_status()
Current WhatsApp link + pause status, with the pairing QR inlined when one is waiting to be scanned. Safe to poll from the dashboard.

### Parameters

This endpoint does not need any parameter.

### Return type

[**models::WhatsappStatus**](WhatsappStatus.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

