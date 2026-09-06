# \FloorTransfersApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancel_transfer**](FloorTransfersApi.md#cancel_transfer) | **POST** /floor/transfers/{id}/cancel | 
[**create_floor_transfer**](FloorTransfersApi.md#create_floor_transfer) | **POST** /floor/transfers | 
[**fulfill_transfer**](FloorTransfersApi.md#fulfill_transfer) | **POST** /floor/transfers/{id}/fulfill | 
[**list_floor_transfers**](FloorTransfersApi.md#list_floor_transfers) | **GET** /floor/transfers | 



## cancel_transfer

> models::TransferView cancel_transfer(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Transfer request ID | [required] |

### Return type

[**models::TransferView**](TransferView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_floor_transfer

> models::TransferView create_floor_transfer(create_floor_transfer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_floor_transfer_request** | [**CreateFloorTransferRequest**](CreateFloorTransferRequest.md) |  | [required] |

### Return type

[**models::TransferView**](TransferView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## fulfill_transfer

> models::TransferView fulfill_transfer(id, fulfill_transfer_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Transfer request ID | [required] |
**fulfill_transfer_request** | [**FulfillTransferRequest**](FulfillTransferRequest.md) |  | [required] |

### Return type

[**models::TransferView**](TransferView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_floor_transfers

> models::TransfersSyncResponse list_floor_transfers(branch_id, since)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**since** | Option<**chrono::DateTime<chrono::FixedOffset>**> | Sync cursor (as on /held-orders). Omit for the waiting queue only. |  |

### Return type

[**models::TransfersSyncResponse**](TransfersSyncResponse.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

