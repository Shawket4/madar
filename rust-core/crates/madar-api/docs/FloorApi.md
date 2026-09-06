# \FloorApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**clear_table**](FloorApi.md#clear_table) | **POST** /floor/tables/{id}/clear | Mark a bussed table ready for the next party.
[**swap_tables**](FloorApi.md#swap_tables) | **POST** /floor/tables/swap | 



## clear_table

> clear_table(id, clear_table_request)
Mark a bussed table ready for the next party.

The ONE human act the derived-status model needs. Everything else about a table's status follows from the ticket on it: seated when one lands, free when nobody vacated, dirty after a checkout. But no server can see that the plates have been cleared, so a person says so.  Deliberately not a set-status endpoint. Its predecessor took any status and wrote it with no lock and no occupancy check, so it could declare a table free while a ticket was open on it. This performs exactly one transition, `dirty` -> `free`, and refuses anything else.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Table ID | [required] |
**clear_table_request** | [**ClearTableRequest**](ClearTableRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## swap_tables

> swap_tables(swap_tables_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**swap_tables_request** | [**SwapTablesRequest**](SwapTablesRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

