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
[**offline_auth_bundle**](OrgsApi.md#offline_auth_bundle) | **GET** /orgs/{id}/offline-auth-bundle | 
[**public_org_brand**](OrgsApi.md#public_org_brand) | **GET** /public/orgs/brand | The shop behind a guest page.
[**update_org**](OrgsApi.md#update_org) | **PATCH** /orgs/{id} | 
[**upload_org_card_image**](OrgsApi.md#upload_org_card_image) | **PUT** /orgs/{id}/card-image | The photograph across the loyalty card — Apple's strip, Google's hero image.
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


## public_org_brand

> models::PublicBrand public_org_brand(org_id, slug)
The shop behind a guest page.

Public and unauthenticated by necessity: it is the first request a customer's browser makes, before there is any notion of a session. Nothing here is private — a name, a logo and three colours are on the shopfront.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**org_id** | Option<**uuid::Uuid**> | The shop, when the page already knows which one it is. |  |
**slug** | Option<**String**> | The first label of the hostname, when it does not — `rue` for `rue.madar-pos.cloud`. |  |

### Return type

[**models::PublicBrand**](PublicBrand.md)

### Authorization

No authorization required

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


## upload_org_card_image

> models::Org upload_org_card_image(id, image)
The photograph across the loyalty card — Apple's strip, Google's hero image.

Own-org, like the logo: it is the shop's own picture of its own coffee, and waiting on a super admin to change it helps nobody. It is stored whatever the branding tier says; whether it REACHES a card is decided later, by the same gate as the logo and the palette.  No palette is derived from it. A photograph has no dominant colour worth painting a card with — that is what the logo is for — and a card whose scheme changed because someone swapped the picture would be a surprise nobody asked for.

### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Organization ID | [required] |
**image** | **std::path::PathBuf** | A wide photograph for the loyalty card. PNG, JPEG or WebP. Required. | [required] |

### Return type

[**models::Org**](Org.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: multipart/form-data
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

