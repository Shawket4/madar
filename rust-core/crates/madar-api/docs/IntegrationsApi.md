# \IntegrationsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**analytics_orders**](IntegrationsApi.md#analytics_orders) | **GET** /integrations/analytics/orders | 
[**create_credential**](IntegrationsApi.md#create_credential) | **POST** /integrations/credentials | 
[**list_credentials**](IntegrationsApi.md#list_credentials) | **GET** /integrations/credentials | 
[**revoke_credential**](IntegrationsApi.md#revoke_credential) | **DELETE** /integrations/credentials/{id} | 
[**rotate_credential**](IntegrationsApi.md#rotate_credential) | **POST** /integrations/credentials/{id}/rotate | 



## analytics_orders

> models::AnalyticsResponse analytics_orders(from, to, limit, offset)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**from** | **chrono::NaiveDate** | First business day to include, `YYYY-MM-DD`, in the branch's timezone. | [required] |
**to** | **chrono::NaiveDate** | Last business day to include, `YYYY-MM-DD`, INCLUSIVE. | [required] |
**limit** | Option<**i64**> | Optional page size (max 5000). Omit for the whole window. |  |
**offset** | Option<**i64**> | Optional row offset, used with `limit`. Defaults to 0. |  |

### Return type

[**models::AnalyticsResponse**](AnalyticsResponse.md)

### Authorization

[basic_integration](../README.md#basic_integration)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_credential

> models::CredentialWithSecret create_credential(create_credential_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_credential_request** | [**CreateCredentialRequest**](CreateCredentialRequest.md) |  | [required] |

### Return type

[**models::CredentialWithSecret**](CredentialWithSecret.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_credentials

> Vec<models::CredentialSummary> list_credentials()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::CredentialSummary>**](CredentialSummary.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## revoke_credential

> revoke_credential(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Credential ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## rotate_credential

> models::CredentialWithSecret rotate_credential(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Credential ID | [required] |

### Return type

[**models::CredentialWithSecret**](CredentialWithSecret.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

