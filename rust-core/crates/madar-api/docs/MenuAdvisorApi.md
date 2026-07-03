# \MenuAdvisorApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create_run_handler**](MenuAdvisorApi.md#create_run_handler) | **POST** /menu-advisor/branches/{branch_id}/runs | 
[**get_active_run_handler**](MenuAdvisorApi.md#get_active_run_handler) | **GET** /menu-advisor/branches/{branch_id}/runs/active | 
[**get_bundle_suggestion_handler**](MenuAdvisorApi.md#get_bundle_suggestion_handler) | **GET** /menu-advisor/bundle-suggestions/{id} | 
[**get_calibration_handler**](MenuAdvisorApi.md#get_calibration_handler) | **GET** /menu-advisor/branches/{branch_id}/calibration | 
[**get_latest_item_kpi_handler**](MenuAdvisorApi.md#get_latest_item_kpi_handler) | **GET** /menu-advisor/branches/{branch_id}/items/{menu_item_id}/sizes/{size_label}/latest-kpi | 
[**get_latest_run_handler**](MenuAdvisorApi.md#get_latest_run_handler) | **GET** /menu-advisor/branches/{branch_id}/runs/latest | 
[**get_price_suggestion_handler**](MenuAdvisorApi.md#get_price_suggestion_handler) | **GET** /menu-advisor/price-suggestions/{id} | 
[**get_removal_scenario_handler**](MenuAdvisorApi.md#get_removal_scenario_handler) | **GET** /menu-advisor/removal-scenarios/{id} | 
[**get_run_handler**](MenuAdvisorApi.md#get_run_handler) | **GET** /menu-advisor/runs/{id} | 
[**list_bundle_suggestions_handler**](MenuAdvisorApi.md#list_bundle_suggestions_handler) | **GET** /menu-advisor/runs/{id}/bundle-suggestions | 
[**list_decisions_handler**](MenuAdvisorApi.md#list_decisions_handler) | **GET** /menu-advisor/branches/{branch_id}/decisions | 
[**list_price_suggestions_handler**](MenuAdvisorApi.md#list_price_suggestions_handler) | **GET** /menu-advisor/runs/{id}/price-suggestions | 
[**list_removal_scenarios_handler**](MenuAdvisorApi.md#list_removal_scenarios_handler) | **GET** /menu-advisor/runs/{id}/removal-scenarios | 
[**list_runs_handler**](MenuAdvisorApi.md#list_runs_handler) | **GET** /menu-advisor/branches/{branch_id}/runs | 
[**record_decision_handler**](MenuAdvisorApi.md#record_decision_handler) | **POST** /menu-advisor/decisions | 
[**set_bundle_promoted_handler**](MenuAdvisorApi.md#set_bundle_promoted_handler) | **POST** /menu-advisor/bundle-suggestions/{id}/promote | 



## create_run_handler

> models::CreateRunResponse create_run_handler(branch_id, create_run_body)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**create_run_body** | [**CreateRunBody**](CreateRunBody.md) |  | [required] |

### Return type

[**models::CreateRunResponse**](CreateRunResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_active_run_handler

> models::PersistedRun get_active_run_handler(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**models::PersistedRun**](PersistedRun.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_bundle_suggestion_handler

> models::BundleSuggestionRecord get_bundle_suggestion_handler(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Bundle suggestion ID | [required] |

### Return type

[**models::BundleSuggestionRecord**](BundleSuggestionRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_calibration_handler

> models::CalibrationSummary get_calibration_handler(branch_id, since)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**since** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Only decisions made at or after this instant. |  |

### Return type

[**models::CalibrationSummary**](CalibrationSummary.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_latest_item_kpi_handler

> models::PriceSuggestionRecord get_latest_item_kpi_handler(branch_id, menu_item_id, size_label)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**menu_item_id** | **uuid::Uuid** | Menu item ID | [required] |
**size_label** | **String** | Size label, e.g. one_size | [required] |

### Return type

[**models::PriceSuggestionRecord**](PriceSuggestionRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_latest_run_handler

> models::PersistedRun get_latest_run_handler(branch_id, any_status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**any_status** | Option<**bool**> | When true, return the latest run regardless of status so the client can show failed runs (error_message) instead of an empty state. |  |

### Return type

[**models::PersistedRun**](PersistedRun.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_price_suggestion_handler

> models::PriceSuggestionRecord get_price_suggestion_handler(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Price suggestion ID | [required] |

### Return type

[**models::PriceSuggestionRecord**](PriceSuggestionRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_removal_scenario_handler

> models::RemovalScenarioRecord get_removal_scenario_handler(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Removal scenario ID | [required] |

### Return type

[**models::RemovalScenarioRecord**](RemovalScenarioRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_run_handler

> models::PersistedRun get_run_handler(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Run ID | [required] |

### Return type

[**models::PersistedRun**](PersistedRun.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_bundle_suggestions_handler

> Vec<models::BundleSuggestionRecord> list_bundle_suggestions_handler(id, missing_costs, focus_menu_item_id, decision_status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Run ID | [required] |
**missing_costs** | Option<**bool**> |  |  |
**focus_menu_item_id** | Option<**uuid::Uuid**> |  |  |
**decision_status** | Option<**String**> | accepted | rejected | ignored | pending |  |

### Return type

[**Vec<models::BundleSuggestionRecord>**](BundleSuggestionRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_decisions_handler

> Vec<models::DecisionRecord> list_decisions_handler(branch_id, since)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**since** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Only decisions made at or after this instant. |  |

### Return type

[**Vec<models::DecisionRecord>**](DecisionRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_price_suggestions_handler

> Vec<models::PriceSuggestionRecord> list_price_suggestions_handler(id, classification_mode, cm_quadrant, revenue_class, action, confidence, category_id, decision_status, search)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Run ID | [required] |
**classification_mode** | Option<**String**> | cm | revenue | insufficient |  |
**cm_quadrant** | Option<**String**> | star | plowhorse | puzzle | dog |  |
**revenue_class** | Option<**String**> | hero | steady | slow | quiet |  |
**action** | Option<**String**> | hold | raise_price | lower_price | bundle | remove | reformulate | monitor |  |
**confidence** | Option<**String**> | low | medium | high |  |
**category_id** | Option<**uuid::Uuid**> |  |  |
**decision_status** | Option<**String**> | accepted | rejected | ignored | pending |  |
**search** | Option<**String**> | Case-insensitive substring match on item name. |  |

### Return type

[**Vec<models::PriceSuggestionRecord>**](PriceSuggestionRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_removal_scenarios_handler

> Vec<models::RemovalScenarioRecord> list_removal_scenarios_handler(id, recommendation, decision_status)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Run ID | [required] |
**recommendation** | Option<**String**> | remove | keep_and_bundle | keep_and_reformulate | no_strong_signal |  |
**decision_status** | Option<**String**> | accepted | rejected | ignored | pending |  |

### Return type

[**Vec<models::RemovalScenarioRecord>**](RemovalScenarioRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_runs_handler

> Vec<models::PersistedRun> list_runs_handler(branch_id, limit, before)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** | Branch ID | [required] |
**limit** | Option<**i64**> | Page size, clamped to [1, 100]. Default 20. |  |
**before** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Return runs started strictly before this instant (pagination cursor). |  |

### Return type

[**Vec<models::PersistedRun>**](PersistedRun.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## record_decision_handler

> models::DecisionRecord record_decision_handler(record_decision_body)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**record_decision_body** | [**RecordDecisionBody**](RecordDecisionBody.md) |  | [required] |

### Return type

[**models::DecisionRecord**](DecisionRecord.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_bundle_promoted_handler

> set_bundle_promoted_handler(id, promote_bundle_body)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Bundle suggestion ID | [required] |
**promote_bundle_body** | [**PromoteBundleBody**](PromoteBundleBody.md) |  | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

