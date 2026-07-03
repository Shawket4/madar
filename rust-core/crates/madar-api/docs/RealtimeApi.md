# \RealtimeApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**stream**](RealtimeApi.md#stream) | **GET** /realtime/stream | SSE stream of all realtime events for a branch, filtered by topic + permission. **Updates-only**: the client seeds current state from the per-feature list endpoints (or `/realtime/snapshot`) first, then connects. On any error/close it re-seeds and reconnects.



## stream

> stream(branch_id, topics)
SSE stream of all realtime events for a branch, filtered by topic + permission. **Updates-only**: the client seeds current state from the per-feature list endpoints (or `/realtime/snapshot`) first, then connects. On any error/close it re-seeds and reconnects.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**topics** | Option<**String**> | Comma-separated topics: `delivery,tickets,kitchen,orders`. Omit to receive every topic the caller is permitted to read. |  |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: text/event-stream, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

