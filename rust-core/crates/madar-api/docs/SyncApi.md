# \SyncApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**pull**](SyncApi.md#pull) | **POST** /sync/pull | 
[**replay_batch**](SyncApi.md#replay_batch) | **POST** /sync/replay/batch | POST /sync/replay/batch



## pull

> models::PullResponse pull(pull_request, since)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**pull_request** | [**PullRequest**](PullRequest.md) |  | [required] |
**since** | Option<**i64**> | Cursor from the previous response's `next`. Absent = full snapshot. |  |

### Return type

[**models::PullResponse**](PullResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## replay_batch

> models::ReplayBatchResponse replay_batch(replay_batch_request)
POST /sync/replay/batch

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**replay_batch_request** | [**ReplayBatchRequest**](ReplayBatchRequest.md) |  | [required] |

### Return type

[**models::ReplayBatchResponse**](ReplayBatchResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

