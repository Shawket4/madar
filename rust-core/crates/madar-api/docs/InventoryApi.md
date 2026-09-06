# \InventoryApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_catalog_item**](InventoryApi.md#create_catalog_item) | **POST** /inventory/orgs/{org_id}/catalog | 
[**create_ingredient_category**](InventoryApi.md#create_ingredient_category) | **POST** /inventory/orgs/{org_id}/categories | 
[**create_transfer**](InventoryApi.md#create_transfer) | **POST** /inventory/transfers | 
[**create_waste**](InventoryApi.md#create_waste) | **POST** /inventory/branches/{branch_id}/waste | 
[**delete_catalog_item**](InventoryApi.md#delete_catalog_item) | **DELETE** /inventory/orgs/{org_id}/catalog/{id} | 
[**delete_ingredient_category**](InventoryApi.md#delete_ingredient_category) | **DELETE** /inventory/orgs/{org_id}/categories/{id} | 
[**delete_transfer**](InventoryApi.md#delete_transfer) | **DELETE** /inventory/transfers/{id} | 
[**get_inventory_settings**](InventoryApi.md#get_inventory_settings) | **GET** /inventory/orgs/{org_id}/settings | 
[**list_branch_stock**](InventoryApi.md#list_branch_stock) | **GET** /inventory/branches/{branch_id}/stock | 
[**list_catalog**](InventoryApi.md#list_catalog) | **GET** /inventory/orgs/{org_id}/catalog | 
[**list_ingredient_categories**](InventoryApi.md#list_ingredient_categories) | **GET** /inventory/orgs/{org_id}/categories | 
[**list_movements**](InventoryApi.md#list_movements) | **GET** /inventory/branches/{branch_id}/movements | 
[**list_transfers**](InventoryApi.md#list_transfers) | **GET** /inventory/branches/{branch_id}/transfers | 
[**list_waste**](InventoryApi.md#list_waste) | **GET** /inventory/branches/{branch_id}/waste | 
[**set_par_levels**](InventoryApi.md#set_par_levels) | **PUT** /inventory/branches/{branch_id}/stock/{org_ingredient_id}/par | 
[**update_catalog_item**](InventoryApi.md#update_catalog_item) | **PATCH** /inventory/orgs/{org_id}/catalog/{id} | 
[**update_ingredient_category**](InventoryApi.md#update_ingredient_category) | **PATCH** /inventory/orgs/{org_id}/categories/{id} | 
[**update_inventory_settings**](InventoryApi.md#update_inventory_settings) | **PUT** /inventory/orgs/{org_id}/settings | 
[**update_transfer**](InventoryApi.md#update_transfer) | **PATCH** /inventory/transfers/{id} | 



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

> Vec<models::BranchStockRow> list_branch_stock(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**Vec<models::BranchStockRow>**](BranchStockRow.md)

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

> Vec<models::StockTransfer> list_transfers(branch_id, direction, limit, offset)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**direction** | Option<**String**> |  |  |
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

