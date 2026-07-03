# \OrdersApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_order**](OrdersApi.md#create_order) | **POST** /orders | 
[**export_orders**](OrdersApi.md#export_orders) | **GET** /orders/export | 
[**get_order**](OrdersApi.md#get_order) | **GET** /orders/{order_id} | 
[**list_orders**](OrdersApi.md#list_orders) | **GET** /orders | 
[**preview_recipe**](OrdersApi.md#preview_recipe) | **POST** /orders/preview-recipe | 
[**void_order**](OrdersApi.md#void_order) | **POST** /orders/{order_id}/void | 



## create_order

> models::OrderFull create_order(create_order_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_order_request** | [**CreateOrderRequest**](CreateOrderRequest.md) |  | [required] |

### Return type

[**models::OrderFull**](OrderFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## export_orders

> models::ExportResponse export_orders(branch_id, shift_id, teller_name, waiter_name, payment_method, status, from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  |  |
**shift_id** | Option<**uuid::Uuid**> |  |  |
**teller_name** | Option<**String**> |  |  |
**waiter_name** | Option<**String**> | Filter by the WAITER who opened the ticket (ILIKE, partial match). |  |
**payment_method** | Option<**String**> |  |  |
**status** | Option<**String**> |  |  |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |

### Return type

[**models::ExportResponse**](ExportResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_order

> models::OrderFull get_order(order_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**order_id** | **uuid::Uuid** | Order ID | [required] |

### Return type

[**models::OrderFull**](OrderFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_orders

> models::PaginatedOrders list_orders(branch_id, shift_id, updated_after, page, per_page, teller_name, waiter_name, payment_method, status, from, to, order_type, channel, include_items)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  |  |
**shift_id** | Option<**uuid::Uuid**> |  |  |
**updated_after** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**page** | Option<**i64**> |  |  |
**per_page** | Option<**i64**> |  |  |
**teller_name** | Option<**String**> |  |  |
**waiter_name** | Option<**String**> | Filter by the WAITER who opened the ticket (ILIKE, partial match). Matches only orders that carry a waiter (dine-in settled from a waiter's ticket). |  |
**payment_method** | Option<**String**> |  |  |
**status** | Option<**String**> |  |  |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**order_type** | Option<**String**> | Filter by order origin: \"dine_in\" or \"delivery\". |  |
**channel** | Option<**String**> | Filter delivery orders by channel: \"in_mall\" or \"outside\". |  |
**include_items** | Option<**bool**> | When true, each order in `data` embeds its full line items (addons/optionals/bundle components) — the response shape becomes [PaginatedOrdersFull]. Lets offline-first clients cache complete orders in one round trip instead of fetching each order separately. |  |

### Return type

[**models::PaginatedOrders**](PaginatedOrders.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## preview_recipe

> Vec<models::PreviewIngredient> preview_recipe(preview_recipe_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**preview_recipe_request** | [**PreviewRecipeRequest**](PreviewRecipeRequest.md) |  | [required] |

### Return type

[**Vec<models::PreviewIngredient>**](PreviewIngredient.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## void_order

> models::Order void_order(order_id, void_order_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**order_id** | **uuid::Uuid** | Order ID | [required] |
**void_order_request** | [**VoidOrderRequest**](VoidOrderRequest.md) |  | [required] |

### Return type

[**models::Order**](Order.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

