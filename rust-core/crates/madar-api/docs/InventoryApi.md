# \InventoryApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**add_to_branch_stock**](InventoryApi.md#add_to_branch_stock) | **POST** /inventory/branches/{branch_id}/stock | 
[**create_catalog_item**](InventoryApi.md#create_catalog_item) | **POST** /inventory/orgs/{org_id}/catalog | 
[**create_transfer**](InventoryApi.md#create_transfer) | **POST** /inventory/transfers | 
[**create_waste**](InventoryApi.md#create_waste) | **POST** /inventory/branches/{branch_id}/waste | 
[**delete_catalog_item**](InventoryApi.md#delete_catalog_item) | **DELETE** /inventory/orgs/{org_id}/catalog/{id} | 
[**delete_transfer**](InventoryApi.md#delete_transfer) | **DELETE** /inventory/transfers/{id} | 
[**get_inventory_settings**](InventoryApi.md#get_inventory_settings) | **GET** /inventory/orgs/{org_id}/settings | 
[**list_branch_stock**](InventoryApi.md#list_branch_stock) | **GET** /inventory/branches/{branch_id}/stock | 
[**list_catalog**](InventoryApi.md#list_catalog) | **GET** /inventory/orgs/{org_id}/catalog | 
[**list_movements**](InventoryApi.md#list_movements) | **GET** /inventory/branches/{branch_id}/movements | 
[**list_transfers**](InventoryApi.md#list_transfers) | **GET** /inventory/branches/{branch_id}/transfers | 
[**list_waste**](InventoryApi.md#list_waste) | **GET** /inventory/branches/{branch_id}/waste | 
[**remove_from_branch_stock**](InventoryApi.md#remove_from_branch_stock) | **DELETE** /inventory/branches/{branch_id}/stock/{id} | 
[**update_branch_stock**](InventoryApi.md#update_branch_stock) | **PATCH** /inventory/branches/{branch_id}/stock/{id} | 
[**update_catalog_item**](InventoryApi.md#update_catalog_item) | **PATCH** /inventory/orgs/{org_id}/catalog/{id} | 
[**update_inventory_settings**](InventoryApi.md#update_inventory_settings) | **PUT** /inventory/orgs/{org_id}/settings | 
[**update_transfer**](InventoryApi.md#update_transfer) | **PATCH** /inventory/transfers/{id} | 



## add_to_branch_stock

> models::BranchInventoryItem add_to_branch_stock(branch_id, add_to_stock_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**add_to_stock_request** | [**AddToStockRequest**](AddToStockRequest.md) |  | [required] |

### Return type

[**models::BranchInventoryItem**](BranchInventoryItem.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_catalog_item

> models::OrgIngredient create_catalog_item(org_id, create_catalog_item_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**create_catalog_item_request** | [**CreateCatalogItemRequest**](CreateCatalogItemRequest.md) |  | [required] |

### Return type

[**models::OrgIngredient**](OrgIngredient.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_transfer

> models::BranchInventoryTransfer create_transfer(create_transfer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_transfer_request** | [**CreateTransferRequest**](CreateTransferRequest.md) |  | [required] |

### Return type

[**models::BranchInventoryTransfer**](BranchInventoryTransfer.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_waste

> models::BranchInventoryMovement create_waste(branch_id, create_waste_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**create_waste_request** | [**CreateWasteRequest**](CreateWasteRequest.md) |  | [required] |

### Return type

[**models::BranchInventoryMovement**](BranchInventoryMovement.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_catalog_item

> delete_catalog_item(org_id, id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**id** | **uuid::Uuid** | Ingredient ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_transfer

> delete_transfer(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Transfer ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_inventory_settings

> models::OrgInventorySettings get_inventory_settings(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

[**models::OrgInventorySettings**](OrgInventorySettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_branch_stock

> Vec<models::BranchInventoryItem> list_branch_stock(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**Vec<models::BranchInventoryItem>**](BranchInventoryItem.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_catalog

> Vec<models::OrgIngredient> list_catalog(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

[**Vec<models::OrgIngredient>**](OrgIngredient.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_movements

> Vec<models::BranchInventoryMovement> list_movements(branch_id, org_ingredient_id, r#type, from, to, page, per_page)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**org_ingredient_id** | Option<**uuid::Uuid**> |  |  |
**r#type** | Option<**String**> |  |  |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**page** | Option<**i64**> |  |  |
**per_page** | Option<**i64**> |  |  |

### Return type

[**Vec<models::BranchInventoryMovement>**](BranchInventoryMovement.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_transfers

> Vec<models::BranchInventoryTransfer> list_transfers(branch_id, direction, limit, offset)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**direction** | Option<**String**> |  |  |
**limit** | Option<**i64**> |  |  |
**offset** | Option<**i64**> |  |  |

### Return type

[**Vec<models::BranchInventoryTransfer>**](BranchInventoryTransfer.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_waste

> Vec<models::BranchInventoryMovement> list_waste(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**Vec<models::BranchInventoryMovement>**](BranchInventoryMovement.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## remove_from_branch_stock

> remove_from_branch_stock(branch_id, id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**id** | **uuid::Uuid** | Stock ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_branch_stock

> models::BranchInventoryItem update_branch_stock(branch_id, id, update_stock_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**id** | **uuid::Uuid** | Stock ID | [required] |
**update_stock_request** | [**UpdateStockRequest**](UpdateStockRequest.md) |  | [required] |

### Return type

[**models::BranchInventoryItem**](BranchInventoryItem.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_catalog_item

> models::OrgIngredient update_catalog_item(org_id, id, update_catalog_item_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**id** | **uuid::Uuid** | Ingredient ID | [required] |
**update_catalog_item_request** | [**UpdateCatalogItemRequest**](UpdateCatalogItemRequest.md) |  | [required] |

### Return type

[**models::OrgIngredient**](OrgIngredient.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_inventory_settings

> models::OrgInventorySettings update_inventory_settings(org_id, update_inventory_settings_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**update_inventory_settings_request** | [**UpdateInventorySettingsRequest**](UpdateInventorySettingsRequest.md) |  | [required] |

### Return type

[**models::OrgInventorySettings**](OrgInventorySettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_transfer

> models::BranchInventoryTransfer update_transfer(id, update_transfer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Transfer ID | [required] |
**update_transfer_request** | [**UpdateTransferRequest**](UpdateTransferRequest.md) |  | [required] |

### Return type

[**models::BranchInventoryTransfer**](BranchInventoryTransfer.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

