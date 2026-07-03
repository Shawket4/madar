# \RecipesApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**delete_addon_ingredient**](RecipesApi.md#delete_addon_ingredient) | **DELETE** /recipes/addons/{addon_item_id} | 
[**delete_drink_recipe**](RecipesApi.md#delete_drink_recipe) | **DELETE** /recipes/drinks/{menu_item_id}/{size} | 
[**list_addon_ingredients**](RecipesApi.md#list_addon_ingredients) | **GET** /recipes/addons/{addon_item_id} | 
[**list_drink_recipes**](RecipesApi.md#list_drink_recipes) | **GET** /recipes/drinks/{menu_item_id} | 
[**upsert_addon_ingredient**](RecipesApi.md#upsert_addon_ingredient) | **POST** /recipes/addons/{addon_item_id} | 
[**upsert_drink_recipe**](RecipesApi.md#upsert_drink_recipe) | **POST** /recipes/drinks/{menu_item_id} | 



## delete_addon_ingredient

> delete_addon_ingredient(ingredient_name, addon_item_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**ingredient_name** | **String** |  | [required] |
**addon_item_id** | **uuid::Uuid** |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_drink_recipe

> delete_drink_recipe(ingredient_name, menu_item_id, size)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**ingredient_name** | **String** |  | [required] |
**menu_item_id** | **uuid::Uuid** |  | [required] |
**size** | **String** |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_addon_ingredients

> Vec<models::AddonIngredient> list_addon_ingredients(addon_item_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**addon_item_id** | **uuid::Uuid** | Addon item ID | [required] |

### Return type

[**Vec<models::AddonIngredient>**](AddonIngredient.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_drink_recipes

> Vec<models::DrinkRecipe> list_drink_recipes(menu_item_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**menu_item_id** | **uuid::Uuid** | Menu item ID | [required] |

### Return type

[**Vec<models::DrinkRecipe>**](DrinkRecipe.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upsert_addon_ingredient

> models::AddonIngredient upsert_addon_ingredient(addon_item_id, upsert_addon_ingredient_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**addon_item_id** | **uuid::Uuid** | Addon item ID | [required] |
**upsert_addon_ingredient_request** | [**UpsertAddonIngredientRequest**](UpsertAddonIngredientRequest.md) |  | [required] |

### Return type

[**models::AddonIngredient**](AddonIngredient.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upsert_drink_recipe

> models::DrinkRecipe upsert_drink_recipe(menu_item_id, upsert_drink_recipe_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**menu_item_id** | **uuid::Uuid** | Menu item ID | [required] |
**upsert_drink_recipe_request** | [**UpsertDrinkRecipeRequest**](UpsertDrinkRecipeRequest.md) |  | [required] |

### Return type

[**models::DrinkRecipe**](DrinkRecipe.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

