# \CostingApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**list_addon_costs**](CostingApi.md#list_addon_costs) | **GET** /costing/addon-items | 
[**list_sku_costs**](CostingApi.md#list_sku_costs) | **GET** /costing/menu-items | 



## list_addon_costs

> Vec<models::AddonCost> list_addon_costs(org_id, branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> | Optional: resolve costs at this branch's actual cost (falling back to the org default per ingredient). Omit for the org default / standard cost. |  |

### Return type

[**Vec<models::AddonCost>**](AddonCost.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_sku_costs

> Vec<models::SkuCost> list_sku_costs(org_id, branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> | Optional: resolve costs at this branch's actual cost (falling back to the org default per ingredient). Omit for the org default / standard cost. |  |

### Return type

[**Vec<models::SkuCost>**](SkuCost.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

