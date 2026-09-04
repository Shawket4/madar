# \InsightsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_decision**](InsightsApi.md#create_decision) | **POST** /insights/decisions | 
[**get_margin_targets**](InsightsApi.md#get_margin_targets) | **GET** /insights/margin-target | 
[**list_decisions**](InsightsApi.md#list_decisions) | **GET** /insights/decisions | 
[**margin_watch**](InsightsApi.md#margin_watch) | **GET** /insights/branches/{branch_id}/margin-watch | 
[**menu_margin_ledger**](InsightsApi.md#menu_margin_ledger) | **GET** /insights/branches/{branch_id}/menu-margin | 
[**put_margin_target**](InsightsApi.md#put_margin_target) | **PUT** /insights/margin-target | 
[**repricing**](InsightsApi.md#repricing) | **GET** /insights/branches/{branch_id}/repricing | 



## create_decision

> models::DecisionOut create_decision(org_id, create_decision_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**create_decision_request** | [**CreateDecisionRequest**](CreateDecisionRequest.md) |  | [required] |

### Return type

[**models::DecisionOut**](DecisionOut.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_margin_targets

> models::MarginTargets get_margin_targets(org_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::MarginTargets**](MarginTargets.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_decisions

> Vec<models::DecisionOut> list_decisions(org_id, branch_id, limit)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**branch_id** | Option<**uuid::Uuid**> |  |  |
**limit** | Option<**i64**> |  |  |

### Return type

[**Vec<models::DecisionOut>**](DecisionOut.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## margin_watch

> models::MarginWatch margin_watch(branch_id, from, to, cost_basis)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch id, or the nil UUID for org-wide | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**cost_basis** | Option<**String**> | `snapshot` (default) | `current`. |  |

### Return type

[**models::MarginWatch**](MarginWatch.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## menu_margin_ledger

> models::MarginLedgerReport menu_margin_ledger(branch_id, from, to, cost_basis)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch id, or the nil UUID for every branch in the org | [required] |
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  |  |
**cost_basis** | Option<**String**> | `snapshot` (default) | `current`. |  |

### Return type

[**models::MarginLedgerReport**](MarginLedgerReport.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_margin_target

> models::MarginTargets put_margin_target(org_id, put_target_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | **uuid::Uuid** |  | [required] |
**put_target_request** | [**PutTargetRequest**](PutTargetRequest.md) |  | [required] |

### Return type

[**models::MarginTargets**](MarginTargets.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## repricing

> models::RepricingReport repricing(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch id (branch-actual costs), or the nil UUID for org-wide (org-standard costs) | [required] |

### Return type

[**models::RepricingReport**](RepricingReport.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

