# \MenuApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**catalog_sync**](MenuApi.md#catalog_sync) | **GET** /catalog/sync | 
[**create_addon_item**](MenuApi.md#create_addon_item) | **POST** /addon-items | 
[**create_addon_slot**](MenuApi.md#create_addon_slot) | **POST** /menu-items/{id}/addon-slots | 
[**create_category**](MenuApi.md#create_category) | **POST** /categories | 
[**create_group**](MenuApi.md#create_group) | **POST** /modifier-groups | 
[**create_menu_item**](MenuApi.md#create_menu_item) | **POST** /menu-items | 
[**create_option**](MenuApi.md#create_option) | **POST** /modifier-groups/{gid}/options | 
[**create_optional_field**](MenuApi.md#create_optional_field) | **POST** /menu-items/{id}/optionals | 
[**delete_addon_item**](MenuApi.md#delete_addon_item) | **DELETE** /addon-items/{id} | 
[**delete_addon_override**](MenuApi.md#delete_addon_override) | **DELETE** /menu-items/{id}/overrides/{override_id} | 
[**delete_addon_slot**](MenuApi.md#delete_addon_slot) | **DELETE** /menu-items/{id}/addon-slots/{slot_id} | 
[**delete_branch_addon_override**](MenuApi.md#delete_branch_addon_override) | **DELETE** /branch-addon-overrides | 
[**delete_branch_menu_override**](MenuApi.md#delete_branch_menu_override) | **DELETE** /branch-menu-overrides | 
[**delete_category**](MenuApi.md#delete_category) | **DELETE** /categories/{id} | 
[**delete_group**](MenuApi.md#delete_group) | **DELETE** /modifier-groups/{gid} | 
[**delete_menu_item**](MenuApi.md#delete_menu_item) | **DELETE** /menu-items/{id} | 
[**delete_option**](MenuApi.md#delete_option) | **DELETE** /modifier-options/{oid} | 
[**delete_optional_field**](MenuApi.md#delete_optional_field) | **DELETE** /menu-items/{id}/optionals/{field_id} | 
[**delete_price_override**](MenuApi.md#delete_price_override) | **DELETE** /menu-price-overrides | 
[**delete_size**](MenuApi.md#delete_size) | **DELETE** /menu-items/{id}/sizes/{sid} | 
[**duplicate_item**](MenuApi.md#duplicate_item) | **POST** /menu-items/{id}/duplicate | 
[**get_item_cost**](MenuApi.md#get_item_cost) | **GET** /menu-items/{id}/cost | 
[**get_menu_item**](MenuApi.md#get_menu_item) | **GET** /menu-items/{id} | 
[**get_studio**](MenuApi.md#get_studio) | **GET** /menu-items/{id}/studio | 
[**list_addon_catalog**](MenuApi.md#list_addon_catalog) | **GET** /addon-items/catalog | 
[**list_addon_items**](MenuApi.md#list_addon_items) | **GET** /addon-items | 
[**list_addon_overrides**](MenuApi.md#list_addon_overrides) | **GET** /menu-items/{id}/overrides | 
[**list_addon_slots**](MenuApi.md#list_addon_slots) | **GET** /menu-items/{id}/addon-slots | 
[**list_branch_addon_overrides**](MenuApi.md#list_branch_addon_overrides) | **GET** /branch-addon-overrides | 
[**list_branch_menu_overrides**](MenuApi.md#list_branch_menu_overrides) | **GET** /branch-menu-overrides | 
[**list_categories**](MenuApi.md#list_categories) | **GET** /categories | 
[**list_groups**](MenuApi.md#list_groups) | **GET** /modifier-groups | 
[**list_menu_catalog**](MenuApi.md#list_menu_catalog) | **GET** /costing/catalog | 
[**list_menu_items**](MenuApi.md#list_menu_items) | **GET** /menu-items | 
[**list_optional_fields**](MenuApi.md#list_optional_fields) | **GET** /menu-items/{id}/optionals | 
[**patch_group**](MenuApi.md#patch_group) | **PATCH** /modifier-groups/{gid} | 
[**patch_option**](MenuApi.md#patch_option) | **PATCH** /modifier-options/{oid} | 
[**put_allowed_addons**](MenuApi.md#put_allowed_addons) | **PUT** /menu-items/{id}/allowed-addons | 
[**put_item_options**](MenuApi.md#put_item_options) | **PUT** /menu-items/{id}/options | 
[**put_modifier_groups**](MenuApi.md#put_modifier_groups) | **PUT** /menu-items/{id}/modifier-groups | 
[**put_option_recipe**](MenuApi.md#put_option_recipe) | **PUT** /modifier-options/{oid}/recipe | 
[**put_price_override**](MenuApi.md#put_price_override) | **PUT** /menu-price-overrides | 
[**put_size_recipe**](MenuApi.md#put_size_recipe) | **PUT** /menu-item-sizes/{size_id}/recipe | 
[**put_sizes**](MenuApi.md#put_sizes) | **PUT** /menu-items/{id}/sizes | 
[**update_addon_item**](MenuApi.md#update_addon_item) | **PATCH** /addon-items/{id} | 
[**update_addon_slot**](MenuApi.md#update_addon_slot) | **PATCH** /menu-items/{id}/addon-slots/{slot_id} | 
[**update_category**](MenuApi.md#update_category) | **PATCH** /categories/{id} | 
[**update_menu_item**](MenuApi.md#update_menu_item) | **PATCH** /menu-items/{id} | 
[**update_optional_field**](MenuApi.md#update_optional_field) | **PATCH** /menu-items/{id}/optionals/{field_id} | 
[**upsert_addon_override**](MenuApi.md#upsert_addon_override) | **POST** /menu-items/{id}/overrides | 
[**upsert_branch_addon_override**](MenuApi.md#upsert_branch_addon_override) | **PUT** /branch-addon-overrides | 
[**upsert_branch_menu_override**](MenuApi.md#upsert_branch_menu_override) | **PUT** /branch-menu-overrides | 
[**upsert_size**](MenuApi.md#upsert_size) | **POST** /menu-items/{id}/sizes | 



## catalog_sync

> models::CatalogSyncResponse catalog_sync(branch_id, channel, since)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch whose resolved prices/availability to return | [required] |
**channel** | Option<**String**> | delivery_channel: in_mall | outside | umbrella | pickup — omit for branch-only resolution (in-store POS) |  |
**since** | Option<**i64**> | Device's cached catalog_revision; == current ⇒ changed:false, no payload |  |

### Return type

[**models::CatalogSyncResponse**](CatalogSyncResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_addon_item

> models::AddonItem create_addon_item(create_addon_item_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_addon_item_request** | [**CreateAddonItemRequest**](CreateAddonItemRequest.md) |  | [required] |

### Return type

[**models::AddonItem**](AddonItem.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_addon_slot

> models::AddonSlot create_addon_slot(id, create_addon_slot_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**create_addon_slot_request** | [**CreateAddonSlotRequest**](CreateAddonSlotRequest.md) |  | [required] |

### Return type

[**models::AddonSlot**](AddonSlot.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_category

> models::Category create_category(create_category_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_category_request** | [**CreateCategoryRequest**](CreateCategoryRequest.md) |  | [required] |

### Return type

[**models::Category**](Category.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_group

> models::GroupOut create_group(create_group_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_group_request** | [**CreateGroupRequest**](CreateGroupRequest.md) |  | [required] |

### Return type

[**models::GroupOut**](GroupOut.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_menu_item

> models::MenuItemFull create_menu_item(create_menu_item_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_menu_item_request** | [**CreateMenuItemRequest**](CreateMenuItemRequest.md) |  | [required] |

### Return type

[**models::MenuItemFull**](MenuItemFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_option

> models::GroupOptionOut create_option(gid, create_option_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**gid** | **uuid::Uuid** | Modifier group ID | [required] |
**create_option_request** | [**CreateOptionRequest**](CreateOptionRequest.md) |  | [required] |

### Return type

[**models::GroupOptionOut**](GroupOptionOut.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_optional_field

> models::OptionalField create_optional_field(id, create_optional_field_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**create_optional_field_request** | [**CreateOptionalFieldRequest**](CreateOptionalFieldRequest.md) |  | [required] |

### Return type

[**models::OptionalField**](OptionalField.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_addon_item

> delete_addon_item(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Addon item ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_addon_override

> delete_addon_override(id, override_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**override_id** | **uuid::Uuid** | Override ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_addon_slot

> delete_addon_slot(id, slot_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**slot_id** | **uuid::Uuid** | Addon slot ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_branch_addon_override

> delete_branch_addon_override(branch_id, addon_item_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**addon_item_id** | **uuid::Uuid** |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_branch_menu_override

> delete_branch_menu_override(branch_id, menu_item_id)


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


## delete_category

> delete_category(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Category ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_group

> delete_group(gid)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**gid** | **uuid::Uuid** | Modifier group ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_menu_item

> delete_menu_item(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_option

> delete_option(oid)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**oid** | **uuid::Uuid** | Modifier option ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_optional_field

> delete_optional_field(id, field_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**field_id** | **uuid::Uuid** | Field ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_price_override

> delete_price_override(price_override_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**price_override_request** | [**PriceOverrideRequest**](PriceOverrideRequest.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_size

> delete_size(id, sid)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**sid** | **uuid::Uuid** | Size ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## duplicate_item

> models::StudioAggregate duplicate_item(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID to duplicate | [required] |

### Return type

[**models::StudioAggregate**](StudioAggregate.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_item_cost

> Vec<models::SizeCostOut> get_item_cost(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |

### Return type

[**Vec<models::SizeCostOut>**](SizeCostOut.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_menu_item

> models::MenuItemFull get_menu_item(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |

### Return type

[**models::MenuItemFull**](MenuItemFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_studio

> models::StudioAggregate get_studio(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |

### Return type

[**models::StudioAggregate**](StudioAggregate.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_addon_catalog

> models::PaginatedAddonItems list_addon_catalog(org_id, addon_type, search, page, per_page, branch_id, overridden, sort)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**addon_type** | Option<**String**> |  |  |
**search** | Option<**String**> | Case-insensitive filter on the addon name. |  |
**page** | Option<**i64**> |  |  |
**per_page** | Option<**i64**> |  |  |
**branch_id** | Option<**uuid::Uuid**> | Enables the per-branch override filter/sort (LEFT JOINs the branch's overrides). |  |
**overridden** | Option<**bool**> | With `branch_id`: true → only addons overridden at the branch; false → only un-overridden; null → all. |  |
**sort** | Option<**String**> | `\"overridden\"` → overridden addons first (needs `branch_id`); otherwise by type/name. |  |

### Return type

[**models::PaginatedAddonItems**](PaginatedAddonItems.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_addon_items

> Vec<models::AddonItem> list_addon_items(org_id, addon_type, branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**addon_type** | Option<**String**> |  |  |
**branch_id** | Option<**uuid::Uuid**> | When set, prices are branch-effective (override replaces default_price) and addons disabled at this branch are excluded — the per-branch addon list the POS consumes. Omitted → the plain org list (legacy behaviour). |  |

### Return type

[**Vec<models::AddonItem>**](AddonItem.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_addon_overrides

> Vec<models::AddonOverride> list_addon_overrides(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |

### Return type

[**Vec<models::AddonOverride>**](AddonOverride.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_addon_slots

> Vec<models::AddonSlot> list_addon_slots(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |

### Return type

[**Vec<models::AddonSlot>**](AddonSlot.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_branch_addon_overrides

> Vec<models::BranchAddonOverride> list_branch_addon_overrides(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::BranchAddonOverride>**](BranchAddonOverride.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_branch_menu_overrides

> Vec<models::BranchMenuOverride> list_branch_menu_overrides(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::BranchMenuOverride>**](BranchMenuOverride.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_categories

> Vec<models::Category> list_categories(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::Category>**](Category.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_groups

> Vec<models::GroupOut> list_groups(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization whose reusable modifier groups to list | [required] |

### Return type

[**Vec<models::GroupOut>**](GroupOut.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_menu_catalog

> models::PaginatedMenuItems list_menu_catalog(org_id, category_id, search, page, per_page, branch_id, overridden, sort)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**category_id** | Option<**uuid::Uuid**> |  |  |
**search** | Option<**String**> | Case-insensitive filter on the item name. |  |
**page** | Option<**i64**> | 1-based page number (default 1). |  |
**per_page** | Option<**i64**> | Page size (default 50, max 500). |  |
**branch_id** | Option<**uuid::Uuid**> | When set, enables the per-branch override filter/sort (LEFT JOINs the branch's overrides). Prices in the response stay org-level. |  |
**overridden** | Option<**bool**> | With `branch_id`: true → only items overridden at the branch; false → only un-overridden; null → all. |  |
**sort** | Option<**String**> | `\"overridden\"` → overridden items first (needs `branch_id`); otherwise A–Z. |  |

### Return type

[**models::PaginatedMenuItems**](PaginatedMenuItems.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_menu_items

> Vec<models::MenuItem> list_menu_items(org_id, category_id, full, branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**category_id** | Option<**uuid::Uuid**> |  |  |
**full** | Option<**bool**> | When true, embed sizes + addon slots + optionals + recipes per item (the shape the POS/teller consumes). Always returns a plain, unpaginated array — the POS depends on this contract. |  |
**branch_id** | Option<**uuid::Uuid**> | When set, prices are branch-effective (branch override replaces base_price) and items disabled at this branch are excluded — the per-branch menu the POS consumes. Omitted → the plain org catalog (legacy behaviour). |  |

### Return type

[**Vec<models::MenuItem>**](MenuItem.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_optional_fields

> Vec<models::OptionalField> list_optional_fields(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |

### Return type

[**Vec<models::OptionalField>**](OptionalField.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## patch_group

> models::GroupOut patch_group(gid, patch_group_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**gid** | **uuid::Uuid** | Modifier group ID | [required] |
**patch_group_request** | [**PatchGroupRequest**](PatchGroupRequest.md) |  | [required] |

### Return type

[**models::GroupOut**](GroupOut.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## patch_option

> models::GroupOptionOut patch_option(oid, patch_option_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**oid** | **uuid::Uuid** | Modifier option ID | [required] |
**patch_option_request** | [**PatchOptionRequest**](PatchOptionRequest.md) |  | [required] |

### Return type

[**models::GroupOptionOut**](GroupOptionOut.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_allowed_addons

> Vec<String> put_allowed_addons(id, put_allowed_addons_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**put_allowed_addons_request** | [**PutAllowedAddonsRequest**](PutAllowedAddonsRequest.md) |  | [required] |

### Return type

**Vec<String>**

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_item_options

> Vec<models::ItemOptionOut> put_item_options(id, put_item_options_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**put_item_options_request** | [**PutItemOptionsRequest**](PutItemOptionsRequest.md) |  | [required] |

### Return type

[**Vec<models::ItemOptionOut>**](ItemOptionOut.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_modifier_groups

> models::StudioAggregate put_modifier_groups(id, put_modifier_groups_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**put_modifier_groups_request** | [**PutModifierGroupsRequest**](PutModifierGroupsRequest.md) |  | [required] |

### Return type

[**models::StudioAggregate**](StudioAggregate.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_option_recipe

> Vec<models::OptionRecipeLineInput> put_option_recipe(oid, option_recipe_line_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**oid** | **uuid::Uuid** | Modifier option ID | [required] |
**option_recipe_line_input** | [**Vec<models::OptionRecipeLineInput>**](OptionRecipeLineInput.md) |  | [required] |

### Return type

[**Vec<models::OptionRecipeLineInput>**](OptionRecipeLineInput.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_price_override

> models::PriceOverrideOut put_price_override(price_override_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**price_override_request** | [**PriceOverrideRequest**](PriceOverrideRequest.md) |  | [required] |

### Return type

[**models::PriceOverrideOut**](PriceOverrideOut.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_size_recipe

> models::RecipeCostResult put_size_recipe(size_id, put_recipe_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**size_id** | **uuid::Uuid** | menu_item_sizes ID | [required] |
**put_recipe_request** | [**PutRecipeRequest**](PutRecipeRequest.md) |  | [required] |

### Return type

[**models::RecipeCostResult**](RecipeCostResult.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_sizes

> models::StudioAggregate put_sizes(id, put_sizes_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**put_sizes_request** | [**PutSizesRequest**](PutSizesRequest.md) |  | [required] |

### Return type

[**models::StudioAggregate**](StudioAggregate.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_addon_item

> models::AddonItem update_addon_item(id, update_addon_item_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Addon item ID | [required] |
**update_addon_item_request** | [**UpdateAddonItemRequest**](UpdateAddonItemRequest.md) |  | [required] |

### Return type

[**models::AddonItem**](AddonItem.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_addon_slot

> models::AddonSlot update_addon_slot(id, slot_id, update_addon_slot_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**slot_id** | **uuid::Uuid** | Addon slot ID | [required] |
**update_addon_slot_request** | [**UpdateAddonSlotRequest**](UpdateAddonSlotRequest.md) |  | [required] |

### Return type

[**models::AddonSlot**](AddonSlot.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_category

> models::Category update_category(id, update_category_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Category ID | [required] |
**update_category_request** | [**UpdateCategoryRequest**](UpdateCategoryRequest.md) |  | [required] |

### Return type

[**models::Category**](Category.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_menu_item

> models::MenuItem update_menu_item(id, update_menu_item_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**update_menu_item_request** | [**UpdateMenuItemRequest**](UpdateMenuItemRequest.md) |  | [required] |

### Return type

[**models::MenuItem**](MenuItem.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_optional_field

> models::OptionalField update_optional_field(id, field_id, update_optional_field_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**field_id** | **uuid::Uuid** | Field ID | [required] |
**update_optional_field_request** | [**UpdateOptionalFieldRequest**](UpdateOptionalFieldRequest.md) |  | [required] |

### Return type

[**models::OptionalField**](OptionalField.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upsert_addon_override

> models::AddonOverride upsert_addon_override(id, upsert_addon_override_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**upsert_addon_override_request** | [**UpsertAddonOverrideRequest**](UpsertAddonOverrideRequest.md) |  | [required] |

### Return type

[**models::AddonOverride**](AddonOverride.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upsert_branch_addon_override

> models::BranchAddonOverride upsert_branch_addon_override(branch_addon_override_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_addon_override_input** | [**BranchAddonOverrideInput**](BranchAddonOverrideInput.md) |  | [required] |

### Return type

[**models::BranchAddonOverride**](BranchAddonOverride.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upsert_branch_menu_override

> models::BranchMenuOverride upsert_branch_menu_override(branch_menu_override_input)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_menu_override_input** | [**BranchMenuOverrideInput**](BranchMenuOverrideInput.md) |  | [required] |

### Return type

[**models::BranchMenuOverride**](BranchMenuOverride.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upsert_size

> models::ItemSize upsert_size(id, upsert_size_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Menu item ID | [required] |
**upsert_size_request** | [**UpsertSizeRequest**](UpsertSizeRequest.md) |  | [required] |

### Return type

[**models::ItemSize**](ItemSize.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

