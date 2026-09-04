# \AiApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**chat**](AiApi.md#chat) | **POST** /ai/chat | 



## chat

> models::AiChatResponse chat(ai_chat_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**ai_chat_request** | [**AiChatRequest**](AiChatRequest.md) |  | [required] |

### Return type

[**models::AiChatResponse**](AiChatResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

