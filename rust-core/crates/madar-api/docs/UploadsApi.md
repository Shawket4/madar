# \UploadsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**upload_menu_item_image**](UploadsApi.md#upload_menu_item_image) | **POST** /uploads/menu-items/{menu_item_id} | 



## upload_menu_item_image

> models::UploadResponse upload_menu_item_image(menu_item_id, image)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**menu_item_id** | **uuid::Uuid** | Menu item ID | [required] |
**image** | **std::path::PathBuf** | Image file. PNG, JPEG, or WebP. Required. | [required] |

### Return type

[**models::UploadResponse**](UploadResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: multipart/form-data
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

