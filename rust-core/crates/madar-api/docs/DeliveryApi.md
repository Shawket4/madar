# \DeliveryApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancel_delivery_order**](DeliveryApi.md#cancel_delivery_order) | **POST** /delivery-orders/{id}/cancel | 
[**create_zone**](DeliveryApi.md#create_zone) | **POST** /delivery/zones | 
[**delete_channel_addon_override**](DeliveryApi.md#delete_channel_addon_override) | **DELETE** /delivery/channel-addon-overrides | 
[**delete_channel_override**](DeliveryApi.md#delete_channel_override) | **DELETE** /delivery/channel-overrides | 
[**delete_zone**](DeliveryApi.md#delete_zone) | **DELETE** /delivery/zones/{id} | 
[**finalize_delivery_order**](DeliveryApi.md#finalize_delivery_order) | **POST** /delivery-orders/{id}/finalize | 
[**get_branch_settings**](DeliveryApi.md#get_branch_settings) | **GET** /delivery/settings | 
[**get_delivery_order**](DeliveryApi.md#get_delivery_order) | **GET** /delivery-orders/{id} | 
[**list_channel_addon_overrides**](DeliveryApi.md#list_channel_addon_overrides) | **GET** /delivery/channel-addon-overrides | 
[**list_channel_overrides**](DeliveryApi.md#list_channel_overrides) | **GET** /delivery/channel-overrides | 
[**list_delivery_orders**](DeliveryApi.md#list_delivery_orders) | **GET** /delivery-orders | 
[**list_zones**](DeliveryApi.md#list_zones) | **GET** /delivery/zones | 
[**put_branch_settings**](DeliveryApi.md#put_branch_settings) | **PUT** /delivery/settings | 
[**set_accepting**](DeliveryApi.md#set_accepting) | **POST** /delivery/accepting | 
[**set_prep_time**](DeliveryApi.md#set_prep_time) | **POST** /delivery-orders/{id}/prep-time | 
[**set_status**](DeliveryApi.md#set_status) | **POST** /delivery-orders/{id}/status | 
[**stream_delivery_orders**](DeliveryApi.md#stream_delivery_orders) | **GET** /delivery-orders/stream | Server-Sent Events stream of delivery-order changes for one branch. Auth is the same Bearer + `delivery_orders:read` + branch-access trio as the list endpoint, enforced before the stream opens. The stream is **updates-only**: the client should `GET /delivery-orders` first to seed the list, then connect. On any error/disconnect the client re-GETs and reconnects.
[**update_zone**](DeliveryApi.md#update_zone) | **PATCH** /delivery/zones/{id} | 
[**upsert_channel_addon_override**](DeliveryApi.md#upsert_channel_addon_override) | **PUT** /delivery/channel-addon-overrides | 
[**upsert_channel_override**](DeliveryApi.md#upsert_channel_override) | **PUT** /delivery/channel-overrides | 



## cancel_delivery_order

> models::DeliveryOrder cancel_delivery_order(id, cancel_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**cancel_input** | [**CancelInput**](CancelInput.md) |  | [required] |

### Return type

[**models::DeliveryOrder**](DeliveryOrder.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_zone

> models::DeliveryZone create_zone(zone_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**zone_input** | [**ZoneInput**](ZoneInput.md) |  | [required] |

### Return type

[**models::DeliveryZone**](DeliveryZone.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_channel_addon_override

> delete_channel_addon_override(branch_id, addon_item_id, channel)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**addon_item_id** | **uuid::Uuid** |  | [required] |
**channel** | **String** |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_channel_override

> delete_channel_override(branch_id, menu_item_id, channel)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**menu_item_id** | **uuid::Uuid** |  | [required] |
**channel** | **String** |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_zone

> delete_zone(branch_id, id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**id** | **uuid::Uuid** |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## finalize_delivery_order

> models::FinalizeResponse finalize_delivery_order(id, finalize_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**finalize_input** | [**FinalizeInput**](FinalizeInput.md) |  | [required] |

### Return type

[**models::FinalizeResponse**](FinalizeResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_branch_settings

> models::BranchDeliverySettings get_branch_settings(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::BranchDeliverySettings**](BranchDeliverySettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_delivery_order

> models::DeliveryOrder get_delivery_order(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::DeliveryOrder**](DeliveryOrder.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_channel_addon_overrides

> Vec<models::ChannelAddonOverride> list_channel_addon_overrides(branch_id, channel)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**channel** | **String** |  | [required] |

### Return type

[**Vec<models::ChannelAddonOverride>**](ChannelAddonOverride.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_channel_overrides

> Vec<models::ChannelMenuOverride> list_channel_overrides(branch_id, channel)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**channel** | **String** |  | [required] |

### Return type

[**Vec<models::ChannelMenuOverride>**](ChannelMenuOverride.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_delivery_orders

> Vec<models::DeliveryOrder> list_delivery_orders(branch_id, status, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**status** | Option<**String**> | Comma-separated statuses to include (default: all). |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::DeliveryOrder>**](DeliveryOrder.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_zones

> Vec<models::DeliveryZone> list_zones(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::DeliveryZone>**](DeliveryZone.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_branch_settings

> models::BranchDeliverySettings put_branch_settings(branch_settings_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_settings_input** | [**BranchSettingsInput**](BranchSettingsInput.md) |  | [required] |

### Return type

[**models::BranchDeliverySettings**](BranchDeliverySettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_accepting

> models::BranchDeliverySettings set_accepting(accepting_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**accepting_input** | [**AcceptingInput**](AcceptingInput.md) |  | [required] |

### Return type

[**models::BranchDeliverySettings**](BranchDeliverySettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_prep_time

> models::DeliveryOrder set_prep_time(id, prep_time_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**prep_time_input** | [**PrepTimeInput**](PrepTimeInput.md) |  | [required] |

### Return type

[**models::DeliveryOrder**](DeliveryOrder.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_status

> models::DeliveryOrder set_status(id, status_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**status_input** | [**StatusInput**](StatusInput.md) |  | [required] |

### Return type

[**models::DeliveryOrder**](DeliveryOrder.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## stream_delivery_orders

> stream_delivery_orders(branch_id)
Server-Sent Events stream of delivery-order changes for one branch. Auth is the same Bearer + `delivery_orders:read` + branch-access trio as the list endpoint, enforced before the stream opens. The stream is **updates-only**: the client should `GET /delivery-orders` first to seed the list, then connect. On any error/disconnect the client re-GETs and reconnects.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: text/event-stream, application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_zone

> models::DeliveryZone update_zone(id, zone_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | [required] |
**zone_input** | [**ZoneInput**](ZoneInput.md) |  | [required] |

### Return type

[**models::DeliveryZone**](DeliveryZone.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upsert_channel_addon_override

> models::ChannelAddonOverride upsert_channel_addon_override(channel_addon_override_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**channel_addon_override_input** | [**ChannelAddonOverrideInput**](ChannelAddonOverrideInput.md) |  | [required] |

### Return type

[**models::ChannelAddonOverride**](ChannelAddonOverride.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upsert_channel_override

> models::ChannelMenuOverride upsert_channel_override(channel_override_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**channel_override_input** | [**ChannelOverrideInput**](ChannelOverrideInput.md) |  | [required] |

### Return type

[**models::ChannelMenuOverride**](ChannelMenuOverride.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

