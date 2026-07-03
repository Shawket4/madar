# \KitchenApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**bump**](KitchenApi.md#bump) | **POST** /kitchen/items/{item_id}/bump | 
[**create_station**](KitchenApi.md#create_station) | **POST** /kitchen/stations | 
[**delete_category_route**](KitchenApi.md#delete_category_route) | **DELETE** /kitchen/routes/category | 
[**delete_item_route**](KitchenApi.md#delete_item_route) | **DELETE** /kitchen/routes/item | 
[**delete_station**](KitchenApi.md#delete_station) | **DELETE** /kitchen/stations/{id} | 
[**feed**](KitchenApi.md#feed) | **GET** /kitchen/orders | Outstanding kitchen tickets for a branch (those with at least one un-bumped, un-voided line — for the given station if provided), oldest first. Seed for the KDS; live updates arrive on `/realtime/stream?topics=kitchen`.
[**get_routing_mode**](KitchenApi.md#get_routing_mode) | **GET** /kitchen/routing-mode | 
[**list_routes**](KitchenApi.md#list_routes) | **GET** /kitchen/routes | 
[**list_stations**](KitchenApi.md#list_stations) | **GET** /kitchen/stations | 
[**put_category_route**](KitchenApi.md#put_category_route) | **PUT** /kitchen/routes/category | 
[**put_item_route**](KitchenApi.md#put_item_route) | **PUT** /kitchen/routes/item | 
[**set_routing_mode**](KitchenApi.md#set_routing_mode) | **PUT** /kitchen/routing-mode | 
[**unbump**](KitchenApi.md#unbump) | **POST** /kitchen/items/{item_id}/unbump | 
[**update_station**](KitchenApi.md#update_station) | **PATCH** /kitchen/stations/{id} | 



## bump

> bump(item_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**item_id** | **uuid::Uuid** | Kitchen line ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_station

> models::KitchenStation create_station(create_station_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_station_request** | [**CreateStationRequest**](CreateStationRequest.md) |  | [required] |

### Return type

[**models::KitchenStation**](KitchenStation.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_category_route

> delete_category_route(branch_id, category_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**category_id** | **uuid::Uuid** |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_item_route

> delete_item_route(branch_id, menu_item_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**menu_item_id** | **uuid::Uuid** |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_station

> delete_station(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Station ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## feed

> Vec<models::KitchenTicketView> feed(branch_id, station_id)
Outstanding kitchen tickets for a branch (those with at least one un-bumped, un-voided line — for the given station if provided), oldest first. Seed for the KDS; live updates arrive on `/realtime/stream?topics=kitchen`.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**station_id** | Option<**uuid::Uuid**> | Optional station filter — only tickets with pending work for this station. (Items are returned in full; the client greys/filters by station.) |  |

### Return type

[**Vec<models::KitchenTicketView>**](KitchenTicketView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_routing_mode

> models::RoutingModeResponse get_routing_mode(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::RoutingModeResponse**](RoutingModeResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_routes

> models::StationRoutes list_routes(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::StationRoutes**](StationRoutes.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_stations

> Vec<models::KitchenStation> list_stations(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::KitchenStation>**](KitchenStation.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_category_route

> put_category_route(category_route_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**category_route_input** | [**CategoryRouteInput**](CategoryRouteInput.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_item_route

> put_item_route(item_route_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**item_route_input** | [**ItemRouteInput**](ItemRouteInput.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_routing_mode

> models::RoutingModeResponse set_routing_mode(set_routing_mode_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**set_routing_mode_request** | [**SetRoutingModeRequest**](SetRoutingModeRequest.md) |  | [required] |

### Return type

[**models::RoutingModeResponse**](RoutingModeResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## unbump

> unbump(item_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**item_id** | **uuid::Uuid** | Kitchen line ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_station

> models::KitchenStation update_station(id, update_station_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Station ID | [required] |
**update_station_request** | [**UpdateStationRequest**](UpdateStationRequest.md) |  | [required] |

### Return type

[**models::KitchenStation**](KitchenStation.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

