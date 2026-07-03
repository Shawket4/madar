# \OrgsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**complete_onboarding**](OrgsApi.md#complete_onboarding) | **POST** /orgs/{id}/onboarding/complete | 
[**create_org**](OrgsApi.md#create_org) | **POST** /orgs | 
[**delete_org**](OrgsApi.md#delete_org) | **DELETE** /orgs/{id} | 
[**get_onboarding**](OrgsApi.md#get_onboarding) | **GET** /orgs/{id}/onboarding | 
[**get_org**](OrgsApi.md#get_org) | **GET** /orgs/{id} | 
[**list_orgs**](OrgsApi.md#list_orgs) | **GET** /orgs | 
[**list_public_orgs**](OrgsApi.md#list_public_orgs) | **GET** /public/orgs | 
[**offline_auth_bundle**](OrgsApi.md#offline_auth_bundle) | **GET** /orgs/{id}/offline-auth-bundle | 
[**update_org**](OrgsApi.md#update_org) | **PATCH** /orgs/{id} | 
[**upload_org_logo**](OrgsApi.md#upload_org_logo) | **PUT** /orgs/{id}/logo | 



## complete_onboarding

> models::OnboardingStatus complete_onboarding(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

[**models::OnboardingStatus**](OnboardingStatus.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_org

> models::Org create_org(name, slug, currency_code, logo, receipt_footer, tax_rate, timezone)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**name** | **String** |  | [required] |
**slug** | **String** |  | [required] |
**currency_code** | Option<**String**> |  |  |
**logo** | Option<**std::path::PathBuf**> | Logo image file. PNG, JPEG, or WebP. Optional — omit the field entirely to create the org without a logo. |  |
**receipt_footer** | Option<**String**> |  |  |
**tax_rate** | Option<**f64**> |  |  |
**timezone** | Option<**String**> |  |  |

### Return type

[**models::Org**](Org.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: multipart/form-data
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_org

> delete_org(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_onboarding

> models::OnboardingStatus get_onboarding(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

[**models::OnboardingStatus**](OnboardingStatus.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_org

> models::Org get_org(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

[**models::Org**](Org.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_orgs

> Vec<models::Org> list_orgs()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::Org>**](Org.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_public_orgs

> Vec<models::PublicOrg> list_public_orgs()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::PublicOrg>**](PublicOrg.md)

### Authorization

No authorization required

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## offline_auth_bundle

> models::OfflineAuthBundle offline_auth_bundle(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Organization ID | [required] |

### Return type

[**models::OfflineAuthBundle**](OfflineAuthBundle.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_org

> models::Org update_org(id, update_org_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Organization ID | [required] |
**update_org_request** | [**UpdateOrgRequest**](UpdateOrgRequest.md) |  | [required] |

### Return type

[**models::Org**](Org.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## upload_org_logo

> models::Org upload_org_logo(id, logo)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Organization ID | [required] |
**logo** | **std::path::PathBuf** | Logo image file. PNG, JPEG, or WebP. Required. | [required] |

### Return type

[**models::Org**](Org.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: multipart/form-data
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

