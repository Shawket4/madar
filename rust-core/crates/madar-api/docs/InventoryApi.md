# \InventoryApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**accept_transfer**](InventoryApi.md#accept_transfer) | **POST** /inventory/transfers/{id}/accept | 
[**archive_catalog_item**](InventoryApi.md#archive_catalog_item) | **POST** /inventory/orgs/{org_id}/catalog/{id}/archive | Archive an ingredient: it leaves pickers, reorder suggestions and (once no branch holds stock) stock-count sheets. Nothing else changes: recipes that use it keep deducting and costing it, every till keeps it in its mirror, history keeps showing it, no movement is posted and no balance moves.
[**cancel_stock_transfer**](InventoryApi.md#cancel_stock_transfer) | **POST** /inventory/transfers/{id}/cancel | 
[**create_catalog_item**](InventoryApi.md#create_catalog_item) | **POST** /inventory/orgs/{org_id}/catalog | 
[**create_ingredient_category**](InventoryApi.md#create_ingredient_category) | **POST** /inventory/orgs/{org_id}/categories | 
[**create_transfer**](InventoryApi.md#create_transfer) | **POST** /inventory/transfers | 
[**create_waste**](InventoryApi.md#create_waste) | **POST** /inventory/branches/{branch_id}/waste | 
[**decline_transfer**](InventoryApi.md#decline_transfer) | **POST** /inventory/transfers/{id}/decline | 
[**delete_catalog_item**](InventoryApi.md#delete_catalog_item) | **DELETE** /inventory/orgs/{org_id}/catalog/{id} | 
[**delete_ingredient_category**](InventoryApi.md#delete_ingredient_category) | **DELETE** /inventory/orgs/{org_id}/categories/{id} | 
[**dispatch_transfer**](InventoryApi.md#dispatch_transfer) | **POST** /inventory/transfers/{id}/dispatch | 
[**get_catalog_item_usage**](InventoryApi.md#get_catalog_item_usage) | **GET** /inventory/orgs/{org_id}/catalog/{id}/usage | 
[**get_inventory_settings**](InventoryApi.md#get_inventory_settings) | **GET** /inventory/orgs/{org_id}/settings | 
[**get_transfer**](InventoryApi.md#get_transfer) | **GET** /inventory/transfers/{id} | 
[**list_branch_stock**](InventoryApi.md#list_branch_stock) | **GET** /inventory/branches/{branch_id}/stock | 
[**list_catalog**](InventoryApi.md#list_catalog) | **GET** /inventory/orgs/{org_id}/catalog | 
[**list_ingredient_categories**](InventoryApi.md#list_ingredient_categories) | **GET** /inventory/orgs/{org_id}/categories | 
[**list_movements**](InventoryApi.md#list_movements) | **GET** /inventory/branches/{branch_id}/movements | 
[**list_transfers**](InventoryApi.md#list_transfers) | **GET** /inventory/branches/{branch_id}/transfers | 
[**list_waste**](InventoryApi.md#list_waste) | **GET** /inventory/branches/{branch_id}/waste | 
[**receive_transfer**](InventoryApi.md#receive_transfer) | **POST** /inventory/transfers/{id}/receive | 
[**record_waste**](InventoryApi.md#record_waste) | **POST** /inventory/waste | POST /inventory/waste — record waste at a branch (ingredient or menu item).
[**replenishment**](InventoryApi.md#replenishment) | **GET** /inventory/warehouses/{warehouse_id}/replenishment | 
[**set_par_levels**](InventoryApi.md#set_par_levels) | **PUT** /inventory/branches/{branch_id}/stock/{org_ingredient_id}/par | 
[**transfer_differences**](InventoryApi.md#transfer_differences) | **GET** /inventory/orgs/{org_id}/transfer-differences | 
[**transfer_locations**](InventoryApi.md#transfer_locations) | **GET** /inventory/orgs/{org_id}/transfer-locations | Every live location of the org, for the other side of a transfer. Someone who works at one shop still sends to, and requests from, the rest; `GET /branches` lists only where the caller works.
[**unarchive_catalog_item**](InventoryApi.md#unarchive_catalog_item) | **POST** /inventory/orgs/{org_id}/catalog/{id}/unarchive | Bring an archived ingredient back: pickers and counts list it again. Its name never left it, so this cannot conflict.
[**update_catalog_item**](InventoryApi.md#update_catalog_item) | **PATCH** /inventory/orgs/{org_id}/catalog/{id} | 
[**update_ingredient_category**](InventoryApi.md#update_ingredient_category) | **PATCH** /inventory/orgs/{org_id}/categories/{id} | 
[**update_inventory_settings**](InventoryApi.md#update_inventory_settings) | **PUT** /inventory/orgs/{org_id}/settings | 
[**update_transfer**](InventoryApi.md#update_transfer) | **PATCH** /inventory/transfers/{id} | 



## accept_transfer

> models::StockTransfer accept_transfer(id, accept_transfer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Transfer ID | [required] |
**accept_transfer_request** | [**AcceptTransferRequest**](AcceptTransferRequest.md) |  | [required] |

### Return type

[**models::StockTransfer**](StockTransfer.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## archive_catalog_item

> models::OrgIngredient archive_catalog_item(org_id, id, archive_ingredient_request)
Archive an ingredient: it leaves pickers, reorder suggestions and (once no branch holds stock) stock-count sheets. Nothing else changes: recipes that use it keep deducting and costing it, every till keeps it in its mirror, history keeps showing it, no movement is posted and no balance moves.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**id** | **uuid::Uuid** | Ingredient ID | [required] |
**archive_ingredient_request** | Option<[**ArchiveIngredientRequest**](ArchiveIngredientRequest.md)> | `{confirm: true}` when the ingredient is still used or holds stock |  |

### Return type

[**models::OrgIngredient**](OrgIngredient.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## cancel_stock_transfer

> models::StockTransfer cancel_stock_transfer(id, close_transfer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Transfer ID | [required] |
**close_transfer_request** | [**CloseTransferRequest**](CloseTransferRequest.md) |  | [required] |

### Return type

[**models::StockTransfer**](StockTransfer.md)

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


## create_ingredient_category

> models::IngredientCategory create_ingredient_category(org_id, create_ingredient_category_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**create_ingredient_category_request** | [**CreateIngredientCategoryRequest**](CreateIngredientCategoryRequest.md) |  | [required] |

### Return type

[**models::IngredientCategory**](IngredientCategory.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_transfer

> models::StockTransfer create_transfer(create_transfer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_transfer_request** | [**CreateTransferRequest**](CreateTransferRequest.md) |  | [required] |

### Return type

[**models::StockTransfer**](StockTransfer.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_waste

> models::StockMovement create_waste(branch_id, create_waste_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**create_waste_request** | [**CreateWasteRequest**](CreateWasteRequest.md) |  | [required] |

### Return type

[**models::StockMovement**](StockMovement.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## decline_transfer

> models::StockTransfer decline_transfer(id, close_transfer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Transfer ID | [required] |
**close_transfer_request** | [**CloseTransferRequest**](CloseTransferRequest.md) |  | [required] |

### Return type

[**models::StockTransfer**](StockTransfer.md)

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


## delete_ingredient_category

> delete_ingredient_category(org_id, id, reassign_to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**id** | **uuid::Uuid** | Category ID | [required] |
**reassign_to** | Option<**uuid::Uuid**> | Category that ingredients in the deleted one move to. Required when the category still has ingredients. |  |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## dispatch_transfer

> models::StockTransfer dispatch_transfer(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Transfer ID | [required] |

### Return type

[**models::StockTransfer**](StockTransfer.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_catalog_item_usage

> models::IngredientUsage get_catalog_item_usage(org_id, id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**id** | **uuid::Uuid** | Ingredient ID | [required] |

### Return type

[**models::IngredientUsage**](IngredientUsage.md)

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


## get_transfer

> models::StockTransfer get_transfer(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Transfer ID | [required] |

### Return type

[**models::StockTransfer**](StockTransfer.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_branch_stock

> Vec<models::BranchStockRow> list_branch_stock(branch_id, status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**status** | Option<[**ArchiveFilter**](ArchiveFilter.md)> | `active` | `archived` | `all`. Omitted = `all`: every non-deleted ingredient, exactly the rows older dashboards and tills read (they look names and costs up in this list, so an archived ingredient a recipe still uses must stay in it). Pickers ask for `active`. |  |

### Return type

[**Vec<models::BranchStockRow>**](BranchStockRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_catalog

> Vec<models::OrgIngredient> list_catalog(org_id, status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**status** | Option<[**ArchiveFilter**](ArchiveFilter.md)> | `active` | `archived` | `all`. Omitted = `all`: every non-deleted ingredient, exactly the rows older dashboards and tills read (they look names and costs up in this list, so an archived ingredient a recipe still uses must stay in it). Pickers ask for `active`. |  |

### Return type

[**Vec<models::OrgIngredient>**](OrgIngredient.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_ingredient_categories

> Vec<models::IngredientCategory> list_ingredient_categories(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

[**Vec<models::IngredientCategory>**](IngredientCategory.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_movements

> Vec<models::StockMovement> list_movements(branch_id, org_ingredient_id, r#type, from, to, page, per_page)


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

[**Vec<models::StockMovement>**](StockMovement.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_transfers

> Vec<models::StockTransfer> list_transfers(branch_id, direction, status, limit, offset)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch or warehouse ID; the nil UUID = every location in the org | [required] |
**direction** | Option<**String**> | `incoming` | `outgoing`; omitted = both. |  |
**status** | Option<**String**> | `requested` | `draft` | `dispatched` | `received` | `cancelled`; omitted = all. |  |
**limit** | Option<**i64**> |  |  |
**offset** | Option<**i64**> |  |  |

### Return type

[**Vec<models::StockTransfer>**](StockTransfer.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_waste

> Vec<models::StockMovement> list_waste(branch_id, limit, offset)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**limit** | Option<**i64**> |  |  |
**offset** | Option<**i64**> |  |  |

### Return type

[**Vec<models::StockMovement>**](StockMovement.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## receive_transfer

> models::StockTransfer receive_transfer(id, receive_transfer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Transfer ID | [required] |
**receive_transfer_request** | [**ReceiveTransferRequest**](ReceiveTransferRequest.md) |  | [required] |

### Return type

[**models::StockTransfer**](StockTransfer.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## record_waste

> models::WasteRecorded record_waste(record_waste_request)
POST /inventory/waste — record waste at a branch (ingredient or menu item).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**record_waste_request** | [**RecordWasteRequest**](RecordWasteRequest.md) |  | [required] |

### Return type

[**models::WasteRecorded**](WasteRecorded.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## replenishment

> Vec<models::ReplenishmentRow> replenishment(warehouse_id, branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**warehouse_id** | **uuid::Uuid** | Warehouse ID | [required] |
**branch_id** | **uuid::Uuid** | The branch to fill from this warehouse. | [required] |

### Return type

[**Vec<models::ReplenishmentRow>**](ReplenishmentRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_par_levels

> models::BranchStockRow set_par_levels(branch_id, org_ingredient_id, set_par_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**org_ingredient_id** | **uuid::Uuid** | Ingredient ID | [required] |
**set_par_request** | [**SetParRequest**](SetParRequest.md) |  | [required] |

### Return type

[**models::BranchStockRow**](BranchStockRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## transfer_differences

> Vec<models::TransferDifferenceRow> transfer_differences(org_id, from, to)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Received on or after (inclusive). |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Received before (exclusive). |  |

### Return type

[**Vec<models::TransferDifferenceRow>**](TransferDifferenceRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## transfer_locations

> Vec<models::TransferLocation> transfer_locations(org_id)
Every live location of the org, for the other side of a transfer. Someone who works at one shop still sends to, and requests from, the rest; `GET /branches` lists only where the caller works.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

[**Vec<models::TransferLocation>**](TransferLocation.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## unarchive_catalog_item

> models::OrgIngredient unarchive_catalog_item(org_id, id)
Bring an archived ingredient back: pickers and counts list it again. Its name never left it, so this cannot conflict.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**id** | **uuid::Uuid** | Ingredient ID | [required] |

### Return type

[**models::OrgIngredient**](OrgIngredient.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
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


## update_ingredient_category

> models::IngredientCategory update_ingredient_category(org_id, id, update_ingredient_category_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**id** | **uuid::Uuid** | Category ID | [required] |
**update_ingredient_category_request** | [**UpdateIngredientCategoryRequest**](UpdateIngredientCategoryRequest.md) |  | [required] |

### Return type

[**models::IngredientCategory**](IngredientCategory.md)

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

> models::StockTransfer update_transfer(id, update_transfer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Transfer ID | [required] |
**update_transfer_request** | [**UpdateTransferRequest**](UpdateTransferRequest.md) |  | [required] |

### Return type

[**models::StockTransfer**](StockTransfer.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

