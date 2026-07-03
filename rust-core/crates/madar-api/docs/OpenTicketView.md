# OpenTicketView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**customer_name** | Option<**String**> |  | [optional]
**guest_count** | Option<**i32**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**items** | [**Vec<models::OpenTicketItemView>**](OpenTicketItemView.md) |  | 
**notes** | Option<**String**> |  | [optional]
**opened_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**opened_by** | **uuid::Uuid** |  | 
**opened_by_name** | Option<**String**> |  | [optional]
**order_id** | Option<**uuid::Uuid**> |  | [optional]
**ready_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**settled_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**status** | **String** |  | 
**subtotal** | **i32** |  | 
**table_id** | Option<**uuid::Uuid**> |  | [optional]
**ticket_ref** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


