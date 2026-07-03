# \ReportsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**branch_addon_sales**](ReportsApi.md#branch_addon_sales) | **GET** /reports/branches/{branch_id}/addons | 
[**branch_bundle_sales**](ReportsApi.md#branch_bundle_sales) | **GET** /reports/branches/{branch_id}/bundles | 
[**branch_combined_item_sales**](ReportsApi.md#branch_combined_item_sales) | **GET** /reports/branches/{branch_id}/items-combined | 
[**branch_consumption**](ReportsApi.md#branch_consumption) | **GET** /reports/branches/{branch_id}/consumption | 
[**branch_delivery_sales**](ReportsApi.md#branch_delivery_sales) | **GET** /reports/branches/{branch_id}/delivery-sales | 
[**branch_inventory_valuation**](ReportsApi.md#branch_inventory_valuation) | **GET** /reports/branches/{branch_id}/inventory-valuation | 
[**branch_low_stock**](ReportsApi.md#branch_low_stock) | **GET** /reports/branches/{branch_id}/low-stock | 
[**branch_menu_engineering**](ReportsApi.md#branch_menu_engineering) | **GET** /reports/branches/{branch_id}/menu-engineering | 
[**branch_sales**](ReportsApi.md#branch_sales) | **GET** /reports/branches/{branch_id}/sales | 
[**branch_sales_peak_hours**](ReportsApi.md#branch_sales_peak_hours) | **GET** /reports/branches/{branch_id}/sales/peak-hours | 
[**branch_sales_timeseries**](ReportsApi.md#branch_sales_timeseries) | **GET** /reports/branches/{branch_id}/sales/timeseries | 
[**branch_shrinkage**](ReportsApi.md#branch_shrinkage) | **GET** /reports/branches/{branch_id}/shrinkage | 
[**branch_stock**](ReportsApi.md#branch_stock) | **GET** /reports/branches/{branch_id}/stock | 
[**branch_teller_stats**](ReportsApi.md#branch_teller_stats) | **GET** /reports/branches/{branch_id}/tellers | 
[**branch_waste_report**](ReportsApi.md#branch_waste_report) | **GET** /reports/branches/{branch_id}/waste-report | 
[**org_branch_comparison**](ReportsApi.md#org_branch_comparison) | **GET** /reports/orgs/{org_id}/comparison | 
[**org_consumption**](ReportsApi.md#org_consumption) | **GET** /reports/orgs/{org_id}/consumption | 
[**org_inventory_valuation**](ReportsApi.md#org_inventory_valuation) | **GET** /reports/orgs/{org_id}/inventory-valuation | 
[**org_low_stock**](ReportsApi.md#org_low_stock) | **GET** /reports/orgs/{org_id}/low-stock | 
[**org_shrinkage**](ReportsApi.md#org_shrinkage) | **GET** /reports/orgs/{org_id}/shrinkage | 
[**org_waste_report**](ReportsApi.md#org_waste_report) | **GET** /reports/orgs/{org_id}/waste-report | 
[**shift_deductions**](ReportsApi.md#shift_deductions) | **GET** /reports/shifts/{shift_id}/deductions | 
[**shift_summary**](ReportsApi.md#shift_summary) | **GET** /reports/shifts/{shift_id}/summary | 



## branch_addon_sales

> Vec<models::AddonSalesRow> branch_addon_sales(branch_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::AddonSalesRow>**](AddonSalesRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_bundle_sales

> Vec<models::BundleSalesRow> branch_bundle_sales(branch_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::BundleSalesRow>**](BundleSalesRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_combined_item_sales

> Vec<models::CombinedItemSalesRow> branch_combined_item_sales(branch_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::CombinedItemSalesRow>**](CombinedItemSalesRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_consumption

> Vec<models::ConsumptionRow> branch_consumption(branch_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::ConsumptionRow>**](ConsumptionRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_delivery_sales

> models::DeliverySalesReport branch_delivery_sales(branch_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**models::DeliverySalesReport**](DeliverySalesReport.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_inventory_valuation

> models::InventoryValuationReport branch_inventory_valuation(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**models::InventoryValuationReport**](InventoryValuationReport.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_low_stock

> Vec<models::LowStockRow> branch_low_stock(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID, or the all-zeros UUID for every branch in the org | [required] |

### Return type

[**Vec<models::LowStockRow>**](LowStockRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_menu_engineering

> models::MenuEngineeringReport branch_menu_engineering(branch_id, from, to, limit, cost_basis)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |
**cost_basis** | Option<**String**> | `snapshot` (default) — COGS from sale-time order snapshots. `current` — COGS from today's recipe rollups. |  |

### Return type

[**models::MenuEngineeringReport**](MenuEngineeringReport.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_sales

> models::BranchSalesReport branch_sales(branch_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**models::BranchSalesReport**](BranchSalesReport.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_sales_peak_hours

> Vec<models::PeakHourPoint> branch_sales_peak_hours(branch_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::PeakHourPoint>**](PeakHourPoint.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_sales_timeseries

> Vec<models::TimeseriesPoint> branch_sales_timeseries(branch_id, from, to, granularity)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**granularity** | Option<**String**> |  |  |

### Return type

[**Vec<models::TimeseriesPoint>**](TimeseriesPoint.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_shrinkage

> Vec<models::ShrinkageRow> branch_shrinkage(branch_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::ShrinkageRow>**](ShrinkageRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_stock

> models::BranchStockReport branch_stock(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**models::BranchStockReport**](BranchStockReport.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_teller_stats

> Vec<models::TellerStats> branch_teller_stats(branch_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::TellerStats>**](TellerStats.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## branch_waste_report

> Vec<models::WasteReportRow> branch_waste_report(branch_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::WasteReportRow>**](WasteReportRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## org_branch_comparison

> models::OrgComparisonReport org_branch_comparison(org_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**models::OrgComparisonReport**](OrgComparisonReport.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## org_consumption

> Vec<models::ConsumptionRow> org_consumption(org_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::ConsumptionRow>**](ConsumptionRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## org_inventory_valuation

> models::InventoryValuationReport org_inventory_valuation(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

[**models::InventoryValuationReport**](InventoryValuationReport.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## org_low_stock

> Vec<models::LowStockRow> org_low_stock(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

[**Vec<models::LowStockRow>**](LowStockRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## org_shrinkage

> Vec<models::ShrinkageRow> org_shrinkage(org_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::ShrinkageRow>**](ShrinkageRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## org_waste_report

> Vec<models::WasteReportRow> org_waste_report(org_id, from, to, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** | Organization ID | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::WasteReportRow>**](WasteReportRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## shift_deductions

> Vec<models::DeductionLogRow> shift_deductions(shift_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**shift_id** | **uuid::Uuid** | Shift ID | [required] |

### Return type

[**Vec<models::DeductionLogRow>**](DeductionLogRow.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## shift_summary

> models::ShiftSummary shift_summary(shift_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**shift_id** | **uuid::Uuid** | Shift ID | [required] |

### Return type

[**models::ShiftSummary**](ShiftSummary.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

