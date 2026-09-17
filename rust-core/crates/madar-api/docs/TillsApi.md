# \TillsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**add_cash_movement**](TillsApi.md#add_cash_movement) | **POST** /tills/{till_id}/cash-movements | 
[**close_preview**](TillsApi.md#close_preview) | **GET** /tills/{till_id}/close-preview | 
[**close_till**](TillsApi.md#close_till) | **POST** /tills/{till_id}/close | 
[**create_spot_check**](TillsApi.md#create_spot_check) | **POST** /tills/{till_id}/spot-checks | 
[**delete_till**](TillsApi.md#delete_till) | **DELETE** /tills/{till_id} | 
[**force_close_till**](TillsApi.md#force_close_till) | **POST** /tills/{till_id}/force-close | 
[**get_current_till**](TillsApi.md#get_current_till) | **GET** /tills/branches/{branch_id}/current | 
[**get_open_bills_notice**](TillsApi.md#get_open_bills_notice) | **GET** /tills/branches/{branch_id}/open-bills-notice | 
[**get_till**](TillsApi.md#get_till) | **GET** /tills/{till_id} | 
[**get_till_report**](TillsApi.md#get_till_report) | **GET** /tills/{till_id}/report | 
[**legacy_list_till_entities**](TillsApi.md#legacy_list_till_entities) | **GET** /tills | `GET /tills` — the removed entity list, synthesized (one \"Till 1\" per branch).
[**list_cash_movements**](TillsApi.md#list_cash_movements) | **GET** /tills/{till_id}/cash-movements | 
[**list_open_tills**](TillsApi.md#list_open_tills) | **GET** /tills/branches/{branch_id}/open | 
[**list_spot_checks**](TillsApi.md#list_spot_checks) | **GET** /tills/{till_id}/spot-checks | 
[**list_tills**](TillsApi.md#list_tills) | **GET** /tills/branches/{branch_id} | 
[**open_till**](TillsApi.md#open_till) | **POST** /tills/branches/{branch_id}/open | 



## add_cash_movement

> models::CashMovement add_cash_movement(till_id, cash_movement_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**till_id** | **uuid::Uuid** | Till ID | [required] |
**cash_movement_request** | [**CashMovementRequest**](CashMovementRequest.md) |  | [required] |

### Return type

[**models::CashMovement**](CashMovement.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## close_preview

> models::CloseTillPreview close_preview(till_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**till_id** | **uuid::Uuid** | Till ID | [required] |

### Return type

[**models::CloseTillPreview**](CloseTillPreview.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## close_till

> models::CloseTillResponse close_till(till_id, close_till_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**till_id** | **uuid::Uuid** | Till ID | [required] |
**close_till_request** | [**CloseTillRequest**](CloseTillRequest.md) |  | [required] |

### Return type

[**models::CloseTillResponse**](CloseTillResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_spot_check

> models::TillSpotCheck create_spot_check(till_id, cash_spot_check_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**till_id** | **uuid::Uuid** | Till ID | [required] |
**cash_spot_check_request** | [**CashSpotCheckRequest**](CashSpotCheckRequest.md) |  | [required] |

### Return type

[**models::TillSpotCheck**](TillSpotCheck.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_till

> delete_till(till_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**till_id** | **uuid::Uuid** | Till ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## force_close_till

> models::Till force_close_till(till_id, force_close_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**till_id** | **uuid::Uuid** | Till ID | [required] |
**force_close_request** | [**ForceCloseRequest**](ForceCloseRequest.md) |  | [required] |

### Return type

[**models::Till**](Till.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_current_till

> models::TillPreFill get_current_till(branch_id, teller_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**teller_id** | Option<**uuid::Uuid**> | Non-teller roles may ask about another person. |  |

### Return type

[**models::TillPreFill**](TillPreFill.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_open_bills_notice

> models::OpenBillsNotice get_open_bills_notice(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**models::OpenBillsNotice**](OpenBillsNotice.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_till

> models::Till get_till(till_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**till_id** | **uuid::Uuid** | Till ID | [required] |

### Return type

[**models::Till**](Till.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_till_report

> models::TillReportResponse get_till_report(till_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**till_id** | **uuid::Uuid** | Till ID | [required] |

### Return type

[**models::TillReportResponse**](TillReportResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## legacy_list_till_entities

> Vec<models::LegacyTill> legacy_list_till_entities(branch_id)
`GET /tills` — the removed entity list, synthesized (one \"Till 1\" per branch).

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  |  |

### Return type

[**Vec<models::LegacyTill>**](LegacyTill.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_cash_movements

> Vec<models::CashMovement> list_cash_movements(till_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**till_id** | **uuid::Uuid** | Till ID | [required] |

### Return type

[**Vec<models::CashMovement>**](CashMovement.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_open_tills

> Vec<models::Till> list_open_tills(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**Vec<models::Till>**](Till.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_spot_checks

> Vec<models::TillSpotCheck> list_spot_checks(till_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**till_id** | **uuid::Uuid** | Till ID | [required] |

### Return type

[**Vec<models::TillSpotCheck>**](TillSpotCheck.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_tills

> models::PaginatedTills list_tills(branch_id, status, teller_id, device_id, flagged, from, to, page, per_page)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID (nil UUID = all branches in org) | [required] |
**status** | Option<**String**> |  |  |
**teller_id** | Option<**uuid::Uuid**> |  |  |
**device_id** | Option<**uuid::Uuid**> |  |  |
**flagged** | Option<**bool**> | Only tills opened while another was open, or with a disagreed reconciliation. |  |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**page** | Option<**i64**> |  |  |
**per_page** | Option<**i64**> |  |  |

### Return type

[**models::PaginatedTills**](PaginatedTills.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## open_till

> models::Till open_till(branch_id, open_till_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**open_till_request** | [**OpenTillRequest**](OpenTillRequest.md) |  | [required] |

### Return type

[**models::Till**](Till.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

