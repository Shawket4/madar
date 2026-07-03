# \ShiftsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**add_cash_movement**](ShiftsApi.md#add_cash_movement) | **POST** /shifts/{shift_id}/cash-movements | 
[**close_shift**](ShiftsApi.md#close_shift) | **POST** /shifts/{shift_id}/close | 
[**delete_shift**](ShiftsApi.md#delete_shift) | **DELETE** /shifts/{shift_id} | 
[**force_close_shift**](ShiftsApi.md#force_close_shift) | **POST** /shifts/{shift_id}/force-close | 
[**get_current_shift**](ShiftsApi.md#get_current_shift) | **GET** /shifts/branches/{branch_id}/current | 
[**get_shift**](ShiftsApi.md#get_shift) | **GET** /shifts/{shift_id} | 
[**get_shift_report**](ShiftsApi.md#get_shift_report) | **GET** /shifts/{shift_id}/report | 
[**list_cash_movements**](ShiftsApi.md#list_cash_movements) | **GET** /shifts/{shift_id}/cash-movements | 
[**list_shifts**](ShiftsApi.md#list_shifts) | **GET** /shifts/branches/{branch_id} | 
[**open_shift**](ShiftsApi.md#open_shift) | **POST** /shifts/branches/{branch_id}/open | 



## add_cash_movement

> models::CashMovement add_cash_movement(shift_id, cash_movement_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**shift_id** | **uuid::Uuid** | Shift ID | [required] |
**cash_movement_request** | [**CashMovementRequest**](CashMovementRequest.md) |  | [required] |

### Return type

[**models::CashMovement**](CashMovement.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## close_shift

> models::CloseShiftResponse close_shift(shift_id, close_shift_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**shift_id** | **uuid::Uuid** | Shift ID | [required] |
**close_shift_request** | [**CloseShiftRequest**](CloseShiftRequest.md) |  | [required] |

### Return type

[**models::CloseShiftResponse**](CloseShiftResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_shift

> delete_shift(shift_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**shift_id** | **uuid::Uuid** | Shift ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## force_close_shift

> models::Shift force_close_shift(shift_id, force_close_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**shift_id** | **uuid::Uuid** | Shift ID | [required] |
**force_close_request** | [**ForceCloseRequest**](ForceCloseRequest.md) |  | [required] |

### Return type

[**models::Shift**](Shift.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_current_shift

> models::ShiftPreFill get_current_shift(branch_id, till_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**till_id** | Option<**uuid::Uuid**> | The device's till (drawer). Narrows the open-shift lookup for managers and scopes the suggested opening cash to that drawer's carryover. Optional — omit to fall back to the branch's default till for the suggestion. |  |

### Return type

[**models::ShiftPreFill**](ShiftPreFill.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_shift

> models::Shift get_shift(shift_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**shift_id** | **uuid::Uuid** | Shift ID | [required] |

### Return type

[**models::Shift**](Shift.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_shift_report

> models::ShiftReportResponse get_shift_report(shift_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**shift_id** | **uuid::Uuid** | Shift ID | [required] |

### Return type

[**models::ShiftReportResponse**](ShiftReportResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_cash_movements

> Vec<models::CashMovement> list_cash_movements(shift_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**shift_id** | **uuid::Uuid** | Shift ID | [required] |

### Return type

[**Vec<models::CashMovement>**](CashMovement.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_shifts

> models::PaginatedShifts list_shifts(branch_id, page, per_page)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID (nil UUID = all branches in org) | [required] |
**page** | Option<**i64**> | 1-based page number. Omit (along with `per_page`) to fetch every shift. |  |
**per_page** | Option<**i64**> | Page size (clamped to [1, 200]). Omit to fetch every shift in one page. |  |

### Return type

[**models::PaginatedShifts**](PaginatedShifts.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## open_shift

> models::Shift open_shift(branch_id, open_shift_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**open_shift_request** | [**OpenShiftRequest**](OpenShiftRequest.md) |  | [required] |

### Return type

[**models::Shift**](Shift.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

