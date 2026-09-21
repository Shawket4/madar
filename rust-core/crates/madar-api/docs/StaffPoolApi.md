# \StaffPoolApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**delete_staff_pool_settings**](StaffPoolApi.md#delete_staff_pool_settings) | **DELETE** /staff-pool/settings | 
[**get_staff_pool_settings**](StaffPoolApi.md#get_staff_pool_settings) | **GET** /staff-pool/settings | 
[**get_staff_pool_today**](StaffPoolApi.md#get_staff_pool_today) | **GET** /staff-pool/today | 
[**list_staff_drinks**](StaffPoolApi.md#list_staff_drinks) | **GET** /staff-pool/drinks | The staff drinks of a branch over a range of business days, newest first.
[**put_staff_pool_settings**](StaffPoolApi.md#put_staff_pool_settings) | **PUT** /staff-pool/settings | 
[**record_staff_drink**](StaffPoolApi.md#record_staff_drink) | **POST** /staff-pool/drinks | 



## delete_staff_pool_settings

> delete_staff_pool_settings(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Omit for the org-wide default; supply a branch for its override. |  |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_staff_pool_settings

> models::StaffPoolSettings get_staff_pool_settings(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Omit for the org-wide default; supply a branch for its override. |  |

### Return type

[**models::StaffPoolSettings**](StaffPoolSettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_staff_pool_today

> models::StaffPoolToday get_staff_pool_today(branch_id, business_date)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**business_date** | Option<**chrono::NaiveDate**> | The business day to ask about. Defaults to the branch's today. |  |

### Return type

[**models::StaffPoolToday**](StaffPoolToday.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_staff_drinks

> Vec<models::StaffDrink> list_staff_drinks(branch_id, from, to, overspent_only)
The staff drinks of a branch over a range of business days, newest first.

This is the whole point of the note: with no \"who is this for\" field by design, the note is the only record of who drank it, and this is where an owner reads it.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**from** | Option<**chrono::NaiveDate**> | Business days, inclusive. Both default to the branch's today. |  |
**to** | Option<**chrono::NaiveDate**> |  |  |
**overspent_only** | Option<**bool**> | Only the drinks that went past the allowance. |  |

### Return type

[**Vec<models::StaffDrink>**](StaffDrink.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_staff_pool_settings

> models::StaffPoolSettings put_staff_pool_settings(staff_pool_settings)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**staff_pool_settings** | [**StaffPoolSettings**](StaffPoolSettings.md) |  | [required] |

### Return type

[**models::StaffPoolSettings**](StaffPoolSettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## record_staff_drink

> models::StaffDrink record_staff_drink(record_staff_drink_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**record_staff_drink_request** | [**RecordStaffDrinkRequest**](RecordStaffDrinkRequest.md) |  | [required] |

### Return type

[**models::StaffDrink**](StaffDrink.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

