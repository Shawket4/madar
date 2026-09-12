# \OpenTicketsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**add_round**](OpenTicketsApi.md#add_round) | **POST** /open-tickets/{id}/rounds | 
[**create_open_ticket**](OpenTicketsApi.md#create_open_ticket) | **POST** /open-tickets | 
[**get_open_ticket**](OpenTicketsApi.md#get_open_ticket) | **GET** /open-tickets/{id} | 
[**list_open_tickets**](OpenTicketsApi.md#list_open_tickets) | **GET** /open-tickets | 
[**move_ticket_table**](OpenTicketsApi.md#move_ticket_table) | **PATCH** /open-tickets/{id}/table | Switch an open ticket to a different table (the \"move table\" button). Works for any live ticket — walk-in dine-in or one auto-opened from a booking. The old table is flagged `dirty` (bus it), the new one `seated`; if the ticket came from a booking, the booking's assignment is kept in sync.
[**public_table**](OpenTicketsApi.md#public_table) | **GET** /public/tables/{id} | 
[**public_table_menu**](OpenTicketsApi.md#public_table_menu) | **GET** /public/tables/{id}/menu | The menu at this table.
[**public_table_order**](OpenTicketsApi.md#public_table_order) | **POST** /public/table-orders | Send this table's order to the kitchen.
[**settle_open_ticket**](OpenTicketsApi.md#settle_open_ticket) | **POST** /open-tickets/{id}/settle | 
[**void_open_ticket**](OpenTicketsApi.md#void_open_ticket) | **POST** /open-tickets/{id}/void | 
[**void_ticket_line**](OpenTicketsApi.md#void_ticket_line) | **POST** /open-tickets/{id}/items/{item_id}/void | 



## add_round

> models::OpenTicketView add_round(id, add_round_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Open ticket ID | [required] |
**add_round_request** | [**AddRoundRequest**](AddRoundRequest.md) |  | [required] |

### Return type

[**models::OpenTicketView**](OpenTicketView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_open_ticket

> models::OpenTicketView create_open_ticket(create_open_ticket_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_open_ticket_request** | [**CreateOpenTicketRequest**](CreateOpenTicketRequest.md) |  | [required] |

### Return type

[**models::OpenTicketView**](OpenTicketView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_open_ticket

> models::OpenTicketView get_open_ticket(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Open ticket ID | [required] |

### Return type

[**models::OpenTicketView**](OpenTicketView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_open_tickets

> Vec<models::OpenTicketView> list_open_tickets(branch_id, status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**status** | Option<**String**> |  |  |

### Return type

[**Vec<models::OpenTicketView>**](OpenTicketView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## move_ticket_table

> models::OpenTicketView move_ticket_table(id, move_ticket_table_request)
Switch an open ticket to a different table (the \"move table\" button). Works for any live ticket — walk-in dine-in or one auto-opened from a booking. The old table is flagged `dirty` (bus it), the new one `seated`; if the ticket came from a booking, the booking's assignment is kept in sync.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Open ticket ID | [required] |
**move_ticket_table_request** | [**MoveTicketTableRequest**](MoveTicketTableRequest.md) |  | [required] |

### Return type

[**models::OpenTicketView**](OpenTicketView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## public_table

> models::PublicTable public_table(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Table ID, from the QR | [required] |

### Return type

[**models::PublicTable**](PublicTable.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## public_table_menu

> models::DeliveryMenu public_table_menu(id)
The menu at this table.

The DINE-IN menu — branch prices, the whole catalogue, no channel discount — because a table's order settles as a dine-in bill. Quoting a customer the in-mall delivery menu and then charging them the till's prices is the same class of mistake as letting the till price its own sales, and it would be invisible until someone compared a receipt to a phone.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Table ID, from the QR | [required] |

### Return type

[**models::DeliveryMenu**](DeliveryMenu.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## public_table_order

> models::OpenTicketView public_table_order(table_order_request)
Send this table's order to the kitchen.

Opens the bill if the table has none, adds a round if it does. Both answer with the bill as it now stands, so the page can show what the table has ordered so far — including the rounds somebody else at the table sent.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**table_order_request** | [**TableOrderRequest**](TableOrderRequest.md) |  | [required] |

### Return type

[**models::OpenTicketView**](OpenTicketView.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## settle_open_ticket

> models::Order settle_open_ticket(id, settle_open_ticket_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Open ticket ID | [required] |
**settle_open_ticket_request** | [**SettleOpenTicketRequest**](SettleOpenTicketRequest.md) |  | [required] |

### Return type

[**models::Order**](Order.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## void_open_ticket

> models::OpenTicketView void_open_ticket(id, void_open_ticket_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Open ticket ID | [required] |
**void_open_ticket_request** | [**VoidOpenTicketRequest**](VoidOpenTicketRequest.md) |  | [required] |

### Return type

[**models::OpenTicketView**](OpenTicketView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## void_ticket_line

> models::OpenTicketView void_ticket_line(id, item_id, void_open_ticket_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Open ticket ID | [required] |
**item_id** | **uuid::Uuid** | Bill line ID | [required] |
**void_open_ticket_request** | [**VoidOpenTicketRequest**](VoidOpenTicketRequest.md) |  | [required] |

### Return type

[**models::OpenTicketView**](OpenTicketView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

