# \PublicApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**api_root**](PublicApi.md#api_root) | **GET** / | What this host is, for a person or an agent that opens it.
[**mcp**](PublicApi.md#mcp) | **POST** /mcp | One JSON-RPC message in, one answer out (a notification gets 202 and no body).
[**mcp_server_card**](PublicApi.md#mcp_server_card) | **GET** /.well-known/mcp/server-card.json | The MCP server card: how to reach this server and what it offers, built from the same tool list `tools/list` answers with, so the two cannot disagree. The marketing site's /.well-known/mcp/server-card.json redirects here.
[**public_openapi**](PublicApi.md#public_openapi) | **GET** /openapi.json | The public part of this API as OpenAPI 3.1.



## api_root

> api_root()
What this host is, for a person or an agent that opens it.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## mcp

> mcp(body)
One JSON-RPC message in, one answer out (a notification gets 202 and no body).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**body** | **serde_json::Value** | One JSON-RPC 2.0 message (MCP Streamable HTTP) | [required] |

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## mcp_server_card

> mcp_server_card()
The MCP server card: how to reach this server and what it offers, built from the same tool list `tools/list` answers with, so the two cannot disagree. The marketing site's /.well-known/mcp/server-card.json redirects here.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## public_openapi

> public_openapi()
The public part of this API as OpenAPI 3.1.

### Parameters

This endpoint does not need any parameter.

### Return type

 (empty response body)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

