# \ReservationsApi

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**assign_tables**](ReservationsApi.md#assign_tables) | **POST** /reservations/{id}/assign | 
[**create_booking**](ReservationsApi.md#create_booking) | **POST** /reservations | 
[**create_floor_table**](ReservationsApi.md#create_floor_table) | **POST** /floor/tables | 
[**create_section**](ReservationsApi.md#create_section) | **POST** /floor/sections | 
[**delete_floor_table**](ReservationsApi.md#delete_floor_table) | **DELETE** /floor/tables/{id} | 
[**delete_section**](ReservationsApi.md#delete_section) | **DELETE** /floor/sections/{id} | 
[**get_reservation_settings**](ReservationsApi.md#get_reservation_settings) | **GET** /floor/reservation-settings | 
[**list_bookings**](ReservationsApi.md#list_bookings) | **GET** /reservations | 
[**list_floor_tables**](ReservationsApi.md#list_floor_tables) | **GET** /floor/tables | 
[**list_sections**](ReservationsApi.md#list_sections) | **GET** /floor/sections | 
[**notify_booking**](ReservationsApi.md#notify_booking) | **POST** /reservations/{id}/notify | 
[**put_reservation_settings**](ReservationsApi.md#put_reservation_settings) | **PUT** /floor/reservation-settings | 
[**save_layout**](ReservationsApi.md#save_layout) | **PUT** /floor/layout | 
[**set_table_status**](ReservationsApi.md#set_table_status) | **PATCH** /floor/tables/{id}/status | 
[**update_booking**](ReservationsApi.md#update_booking) | **PATCH** /reservations/{id} | 
[**update_floor_table**](ReservationsApi.md#update_floor_table) | **PATCH** /floor/tables/{id} | 
[**update_section**](ReservationsApi.md#update_section) | **PATCH** /floor/sections/{id} | 



## assign_tables

> models::BookingView assign_tables(id, assign_tables_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Booking ID | [required] |
**assign_tables_request** | [**AssignTablesRequest**](AssignTablesRequest.md) |  | [required] |

### Return type

[**models::BookingView**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_booking

> models::BookingView create_booking(create_booking_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_booking_request** | [**CreateBookingRequest**](CreateBookingRequest.md) |  | [required] |

### Return type

[**models::BookingView**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_floor_table

> models::FloorTable create_floor_table(create_floor_table_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_floor_table_request** | [**CreateFloorTableRequest**](CreateFloorTableRequest.md) |  | [required] |

### Return type

[**models::FloorTable**](FloorTable.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## create_section

> models::FloorSection create_section(create_section_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**create_section_request** | [**CreateSectionRequest**](CreateSectionRequest.md) |  | [required] |

### Return type

[**models::FloorSection**](FloorSection.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_floor_table

> delete_floor_table(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Table ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## delete_section

> delete_section(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Section ID | [required] |

### Return type

 (empty response body)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## get_reservation_settings

> models::ReservationSettings get_reservation_settings(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**models::ReservationSettings**](ReservationSettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_bookings

> Vec<models::BookingView> list_bookings(branch_id, status, date)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**status** | Option<**String**> |  |  |
**date** | Option<**chrono::NaiveDate**> | Filter reservations to this calendar date (YYYY-MM-DD). Omit for the live board (everything not yet completed/cancelled/no_show). |  |

### Return type

[**Vec<models::BookingView>**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_floor_tables

> Vec<models::FloorTable> list_floor_tables(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::FloorTable>**](FloorTable.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## list_sections

> Vec<models::FloorSection> list_sections(branch_id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |

### Return type

[**Vec<models::FloorSection>**](FloorSection.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## notify_booking

> models::BookingView notify_booking(id)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Booking ID | [required] |

### Return type

[**models::BookingView**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: Not defined
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## put_reservation_settings

> models::ReservationSettings put_reservation_settings(branch_id, update_settings_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | [required] |
**update_settings_request** | [**UpdateSettingsRequest**](UpdateSettingsRequest.md) |  | [required] |

### Return type

[**models::ReservationSettings**](ReservationSettings.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## save_layout

> Vec<models::FloorTable> save_layout(save_layout_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**save_layout_request** | [**SaveLayoutRequest**](SaveLayoutRequest.md) |  | [required] |

### Return type

[**Vec<models::FloorTable>**](FloorTable.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## set_table_status

> models::FloorTable set_table_status(id, set_table_status_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Table ID | [required] |
**set_table_status_request** | [**SetTableStatusRequest**](SetTableStatusRequest.md) |  | [required] |

### Return type

[**models::FloorTable**](FloorTable.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_booking

> models::BookingView update_booking(id, update_booking_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Booking ID | [required] |
**update_booking_request** | [**UpdateBookingRequest**](UpdateBookingRequest.md) |  | [required] |

### Return type

[**models::BookingView**](BookingView.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_floor_table

> models::FloorTable update_floor_table(id, update_floor_table_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Table ID | [required] |
**update_floor_table_request** | [**UpdateFloorTableRequest**](UpdateFloorTableRequest.md) |  | [required] |

### Return type

[**models::FloorTable**](FloorTable.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)


## update_section

> models::FloorSection update_section(id, update_section_request)


### Parameters


Name | Type | Description  | Required | Notes
------------- | ------------- | ------------- | ------------- | -------------
**id** | **uuid::Uuid** | Section ID | [required] |
**update_section_request** | [**UpdateSectionRequest**](UpdateSectionRequest.md) |  | [required] |

### Return type

[**models::FloorSection**](FloorSection.md)

### Authorization

[bearer_jwt](../README.md#bearer_jwt)

### HTTP request headers

- **Content-Type**: application/json
- **Accept**: application/json

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

