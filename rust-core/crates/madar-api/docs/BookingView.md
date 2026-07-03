# BookingView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**arrived_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**branch_id** | **uuid::Uuid** |  | 
**cancelled_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**completed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**customer_lat** | Option<**f64**> |  | [optional]
**customer_lng** | Option<**f64**> |  | [optional]
**customer_name** | **String** |  | 
**customer_phone** | **String** |  | 
**id** | **uuid::Uuid** |  | 
**kind** | **String** |  | 
**no_show_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**notes** | Option<**String**> |  | [optional]
**notified_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**otp_verified** | **bool** |  | 
**party_size** | **i32** |  | 
**quoted_ready_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**reserved_for** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**seated_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**source** | **String** |  | 
**status** | **String** |  | 
**table_ids** | **Vec<uuid::Uuid>** | Assigned table ids (multiple ⇒ merged tables). | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


