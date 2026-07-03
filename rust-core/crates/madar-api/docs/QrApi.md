# \QrApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**branch_qr**](QrApi.md#branch_qr) | **GET** /branches/{id}/qr | 
[**create_marketing_link**](QrApi.md#create_marketing_link) | **POST** /qr/links | 
[**create_table**](QrApi.md#create_table) | **POST** /branches/{id}/tables | 
[**delete_table**](QrApi.md#delete_table) | **DELETE** /branches/{id}/tables/{tid} | 
[**delivery_order_qr**](QrApi.md#delivery_order_qr) | **GET** /delivery-orders/{id}/qr | 
[**list_marketing_links**](QrApi.md#list_marketing_links) | **GET** /qr/links | 
[**list_tables**](QrApi.md#list_tables) | **GET** /branches/{id}/tables | 
[**org_qr**](QrApi.md#org_qr) | **GET** /orgs/{id}/qr | 
[**table_qr**](QrApi.md#table_qr) | **GET** /branches/{id}/tables/{tid}/qr | 



## branch_qr

> models::QrResponse branch_qr(id, card, caption, dpi, bleed_mm, crop_marks, svg, module_px, slug, place_name, floor, unit_number)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Branch ID | [required] |
**card** | Option<**bool**> | `true` (default) → branded A6 card PNG; `false` → plain receipt QR PNG. |  |
**caption** | Option<**String**> | Dynamic caption line beneath the tagline (A6 card only). |  |
**dpi** | Option<**u32**> | Raster DPI for the A6 card (clamped 72–2400). Default 600. |  |
**bleed_mm** | Option<**f32**> | Print bleed in mm (A6 card only). Default 0. |  |
**crop_marks** | Option<**bool**> | Draw crop marks (A6 card, only meaningful when `bleed_mm > 0`). |  |
**svg** | Option<**bool**> | Return the A6 card as SVG (`data:image/svg+xml;base64,…`). Default false. |  |
**module_px** | Option<**u32**> | Pixels per module for the plain receipt QR (1–40). Default 16. |  |
**slug** | Option<**String**> |  |  |
**place_name** | Option<**String**> | Shop or company name inside the mall (e.g. \"Starbucks Kiosk 3\"). |  |
**floor** | Option<**String**> | Floor (e.g. \"Ground Floor\"). |  |
**unit_number** | Option<**String**> | Unit or office number (e.g. \"Unit 42\"). |  |

### Return type

[**models::QrResponse**](QrResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_marketing_link

> models::QrResponse create_marketing_link(create_marketing_link_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_marketing_link_request** | [**CreateMarketingLinkRequest**](CreateMarketingLinkRequest.md) |  | [required] |

### Return type

[**models::QrResponse**](QrResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_table

> models::BranchTable create_table(id, create_table_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Branch ID | [required] |
**create_table_request** | [**CreateTableRequest**](CreateTableRequest.md) |  | [required] |

### Return type

[**models::BranchTable**](BranchTable.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_table

> delete_table(id, tid)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Branch ID | [required] |
**tid** | **uuid::Uuid** | Table ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delivery_order_qr

> models::QrResponse delivery_order_qr(id, card, caption, dpi, bleed_mm, crop_marks, svg, module_px)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Delivery order ID | [required] |
**card** | Option<**bool**> | `true` (default) → branded A6 card PNG; `false` → plain receipt QR PNG. |  |
**caption** | Option<**String**> | Dynamic caption line beneath the tagline (A6 card only). |  |
**dpi** | Option<**u32**> | Raster DPI for the A6 card (clamped 72–2400). Default 600. |  |
**bleed_mm** | Option<**f32**> | Print bleed in mm (A6 card only). Default 0. |  |
**crop_marks** | Option<**bool**> | Draw crop marks (A6 card, only meaningful when `bleed_mm > 0`). |  |
**svg** | Option<**bool**> | Return the A6 card as SVG (`data:image/svg+xml;base64,…`). Default false. |  |
**module_px** | Option<**u32**> | Pixels per module for the plain receipt QR (1–40). Default 16. |  |

### Return type

[**models::QrResponse**](QrResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_marketing_links

> Vec<models::MarketingLink> list_marketing_links()


### Parameters

This endpoint does not need any parameter.

### Return type

[**Vec<models::MarketingLink>**](MarketingLink.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_tables

> Vec<models::BranchTable> list_tables(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Branch ID | [required] |

### Return type

[**Vec<models::BranchTable>**](BranchTable.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## org_qr

> models::QrResponse org_qr(id, card, caption, dpi, bleed_mm, crop_marks, svg, module_px)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Organisation ID | [required] |
**card** | Option<**bool**> | `true` (default) → branded A6 card PNG; `false` → plain receipt QR PNG. |  |
**caption** | Option<**String**> | Dynamic caption line beneath the tagline (A6 card only). |  |
**dpi** | Option<**u32**> | Raster DPI for the A6 card (clamped 72–2400). Default 600. |  |
**bleed_mm** | Option<**f32**> | Print bleed in mm (A6 card only). Default 0. |  |
**crop_marks** | Option<**bool**> | Draw crop marks (A6 card, only meaningful when `bleed_mm > 0`). |  |
**svg** | Option<**bool**> | Return the A6 card as SVG (`data:image/svg+xml;base64,…`). Default false. |  |
**module_px** | Option<**u32**> | Pixels per module for the plain receipt QR (1–40). Default 16. |  |

### Return type

[**models::QrResponse**](QrResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## table_qr

> models::QrResponse table_qr(id, tid, card, caption, dpi, bleed_mm, crop_marks, svg, module_px)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Branch ID | [required] |
**tid** | **uuid::Uuid** | Table ID | [required] |
**card** | Option<**bool**> | `true` (default) → branded A6 card PNG; `false` → plain receipt QR PNG. |  |
**caption** | Option<**String**> | Dynamic caption line beneath the tagline (A6 card only). |  |
**dpi** | Option<**u32**> | Raster DPI for the A6 card (clamped 72–2400). Default 600. |  |
**bleed_mm** | Option<**f32**> | Print bleed in mm (A6 card only). Default 0. |  |
**crop_marks** | Option<**bool**> | Draw crop marks (A6 card, only meaningful when `bleed_mm > 0`). |  |
**svg** | Option<**bool**> | Return the A6 card as SVG (`data:image/svg+xml;base64,…`). Default false. |  |
**module_px** | Option<**u32**> | Pixels per module for the plain receipt QR (1–40). Default 16. |  |

### Return type

[**models::QrResponse**](QrResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

