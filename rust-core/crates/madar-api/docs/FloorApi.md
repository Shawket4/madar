# \FloorApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**clear_table**](FloorApi.md#clear_table) | **POST** /floor/tables/{id}/clear | Mark a bussed table ready for the next party.
[**hold_table**](FloorApi.md#hold_table) | **POST** /floor/tables/{id}/hold | Take a table. THE seating primitive.
[**release_table**](FloorApi.md#release_table) | **POST** /floor/tables/{id}/release | Give back a table a till was holding for its own parked order.
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


## hold_table

> hold_table(id, hold_table_request)
Take a table. THE seating primitive.

Occupancy travels on its own here, carrying nothing about why. Two things use it:    * A PARTY SITTING DOWN. They have ordered nothing yet, so there is no     bill — a ticket starts with their first round and claims this table on     the way in. Seating used to open an empty ticket instead, which put a     zero-value bill in every report and made a party who changed their mind     and left something you had to VOID.   * A PARKED CART. Device-local by design: the order, its lines and its     money never leave the till. But the table is not the till's private     business, and while it stayed local the dashboard's floor and every     other terminal were told a table with somebody's order waiting on it was     free.  In both cases the server learns that the table is taken and nothing whatever about what is on it.  Like `clear_table`, and for the reason written there, this is not a set-status endpoint: exactly one transition, `free` -> `seated`, refused from anything else. A table a ticket is already on stays the ticket's.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Table ID | [required] |
**hold_table_request** | [**HoldTableRequest**](HoldTableRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## release_table

> release_table(id, release_table_request)
Give back a table a till was holding for its own parked order.

The counterpart to `hold_table`: the hold moved to another table, was checked out, or was discarded. Exactly one transition out of `seated` -- to `free`, or to `dirty` when `bus` says the party ate -- and never over a live ticket — if one has landed since, the ticket owns the table and this is a no-op rather than a way to free an occupied table.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Table ID | [required] |
**release_table_request** | [**ReleaseTableRequest**](ReleaseTableRequest.md) |  | [required] |

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

