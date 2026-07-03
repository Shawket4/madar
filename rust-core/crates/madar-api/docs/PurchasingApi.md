# \PurchasingApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancel_purchase_order**](PurchasingApi.md#cancel_purchase_order) | **POST** /purchasing/orders/{id}/cancel | 
[**create_purchase_order**](PurchasingApi.md#create_purchase_order) | **POST** /purchasing/branches/{branch_id}/orders | 
[**create_return**](PurchasingApi.md#create_return) | **POST** /purchasing/branches/{branch_id}/returns | Return stock to a supplier: decrements branch stock and posts a 'purchase_return' movement per line, recorded as a goods receipt with is_return = true. Returns remove stock at its current cost (WAC unchanged).
[**create_supplier**](PurchasingApi.md#create_supplier) | **POST** /purchasing/orgs/{org_id}/suppliers | 
[**delete_supplier**](PurchasingApi.md#delete_supplier) | **DELETE** /purchasing/suppliers/{id} | 
[**get_purchase_order**](PurchasingApi.md#get_purchase_order) | **GET** /purchasing/orders/{id} | 
[**list_org_purchase_orders**](PurchasingApi.md#list_org_purchase_orders) | **GET** /purchasing/orgs/{org_id}/orders | 
[**list_po_receipts**](PurchasingApi.md#list_po_receipts) | **GET** /purchasing/orders/{id}/receipts | Per-delivery goods-receipt records for a purchase order (multi-shipment audit trail, each with the actual received quantity + cost per line).
[**list_purchase_orders**](PurchasingApi.md#list_purchase_orders) | **GET** /purchasing/branches/{branch_id}/orders | 
[**list_suppliers**](PurchasingApi.md#list_suppliers) | **GET** /purchasing/orgs/{org_id}/suppliers | 
[**receive_purchase_order**](PurchasingApi.md#receive_purchase_order) | **POST** /purchasing/orders/{id}/receive | 
[**reorder_suggestions**](PurchasingApi.md#reorder_suggestions) | **GET** /purchasing/branches/{branch_id}/reorder-suggestions | Ingredients at/below their reorder point (par_min, else reorder_threshold), with the quantity to reach the order-up-to level (par_max), grouped by the ingredient's default supplier — the basis for one-click \"create PO\".
[**submit_purchase_order**](PurchasingApi.md#submit_purchase_order) | **POST** /purchasing/orders/{id}/submit | Place a draft PO with the supplier: `draft → ordered`. Makes \"ordered, awaiting goods\" a distinct, queryable state (outstanding-orders views) vs a draft still being built. Receiving is still allowed directly from draft for workflows that don't formally place orders first.
[**update_supplier**](PurchasingApi.md#update_supplier) | **PATCH** /purchasing/suppliers/{id} | 



## cancel_purchase_order

> models::PurchaseOrder cancel_purchase_order(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Purchase order ID | [required] |

### Return type

[**models::PurchaseOrder**](PurchaseOrder.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_purchase_order

> models::PurchaseOrderFull create_purchase_order(branch_id, create_purchase_order_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**create_purchase_order_request** | [**CreatePurchaseOrderRequest**](CreatePurchaseOrderRequest.md) |  | [required] |

### Return type

[**models::PurchaseOrderFull**](PurchaseOrderFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_return

> models::GoodsReceipt create_return(branch_id, create_return_request)
Return stock to a supplier: decrements branch stock and posts a 'purchase_return' movement per line, recorded as a goods receipt with is_return = true. Returns remove stock at its current cost (WAC unchanged).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**create_return_request** | [**CreateReturnRequest**](CreateReturnRequest.md) |  | [required] |

### Return type

[**models::GoodsReceipt**](GoodsReceipt.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_supplier

> models::Supplier create_supplier(org_id, create_supplier_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**create_supplier_request** | [**CreateSupplierRequest**](CreateSupplierRequest.md) |  | [required] |

### Return type

[**models::Supplier**](Supplier.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_supplier

> delete_supplier(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Supplier ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_purchase_order

> models::PurchaseOrderFull get_purchase_order(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Purchase order ID | [required] |

### Return type

[**models::PurchaseOrderFull**](PurchaseOrderFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_org_purchase_orders

> Vec<models::PurchaseOrder> list_org_purchase_orders(org_id, status, expected_before)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**status** | Option<**String**> | Filter by status: draft | ordered | partially_received | received | cancelled. |  |
**expected_before** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Only orders expected on or before this instant (for \"arriving by\" views). |  |

### Return type

[**Vec<models::PurchaseOrder>**](PurchaseOrder.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_po_receipts

> Vec<models::GoodsReceipt> list_po_receipts(id)
Per-delivery goods-receipt records for a purchase order (multi-shipment audit trail, each with the actual received quantity + cost per line).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Purchase order ID | [required] |

### Return type

[**Vec<models::GoodsReceipt>**](GoodsReceipt.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_purchase_orders

> Vec<models::PurchaseOrder> list_purchase_orders(branch_id, status, expected_before)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**status** | Option<**String**> | Filter by status: draft | ordered | partially_received | received | cancelled. |  |
**expected_before** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Only orders expected on or before this instant (for \"arriving by\" views). |  |

### Return type

[**Vec<models::PurchaseOrder>**](PurchaseOrder.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_suppliers

> Vec<models::Supplier> list_suppliers(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

[**Vec<models::Supplier>**](Supplier.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## receive_purchase_order

> models::PurchaseOrderFull receive_purchase_order(id, receive_purchase_order_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Purchase order ID | [required] |
**receive_purchase_order_request** | [**ReceivePurchaseOrderRequest**](ReceivePurchaseOrderRequest.md) |  | [required] |

### Return type

[**models::PurchaseOrderFull**](PurchaseOrderFull.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## reorder_suggestions

> Vec<models::ReorderSuggestion> reorder_suggestions(branch_id)
Ingredients at/below their reorder point (par_min, else reorder_threshold), with the quantity to reach the order-up-to level (par_max), grouped by the ingredient's default supplier — the basis for one-click \"create PO\".

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**Vec<models::ReorderSuggestion>**](ReorderSuggestion.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## submit_purchase_order

> models::PurchaseOrder submit_purchase_order(id)
Place a draft PO with the supplier: `draft → ordered`. Makes \"ordered, awaiting goods\" a distinct, queryable state (outstanding-orders views) vs a draft still being built. Receiving is still allowed directly from draft for workflows that don't formally place orders first.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Purchase order ID | [required] |

### Return type

[**models::PurchaseOrder**](PurchaseOrder.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_supplier

> models::Supplier update_supplier(id, update_supplier_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Supplier ID | [required] |
**update_supplier_request** | [**UpdateSupplierRequest**](UpdateSupplierRequest.md) |  | [required] |

### Return type

[**models::Supplier**](Supplier.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

