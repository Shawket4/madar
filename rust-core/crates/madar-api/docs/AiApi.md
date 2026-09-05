# \AiApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**chat**](AiApi.md#chat) | **POST** /ai/chat | 
[**chat_stream**](AiApi.md#chat_stream) | **POST** /ai/chat/stream | 
[**delete_conversation**](AiApi.md#delete_conversation) | **DELETE** /ai/conversations/{id} | 
[**get_conversation**](AiApi.md#get_conversation) | **GET** /ai/conversations/{id} | 
[**list_conversations**](AiApi.md#list_conversations) | **GET** /ai/conversations | 
[**rename_conversation**](AiApi.md#rename_conversation) | **PATCH** /ai/conversations/{id} | 



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


## chat_stream

> chat_stream(ai_chat_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**ai_chat_request** | [**AiChatRequest**](AiChatRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: text/event-stream, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_conversation

> delete_conversation(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Conversation id | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_conversation

> models::ConversationDetail get_conversation(id, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Conversation id | [required] |
**limit** | Option<**i64**> | How many of the most recent turns to return (default 50, max 200). |  |

### Return type

[**models::ConversationDetail**](ConversationDetail.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_conversations

> models::ConversationList list_conversations(limit, offset)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**limit** | Option<**i64**> | Page size (default 30, max 100). |  |
**offset** | Option<**i64**> |  |  |

### Return type

[**models::ConversationList**](ConversationList.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## rename_conversation

> rename_conversation(id, rename_conversation_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Conversation id | [required] |
**rename_conversation_request** | [**RenameConversationRequest**](RenameConversationRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

