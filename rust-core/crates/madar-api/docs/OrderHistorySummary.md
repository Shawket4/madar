# OrderHistorySummary

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**address_line** | Option<**String**> |  | [optional]
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**channel** | **String** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**customer_lat** | Option<**f64**> |  | [optional]
**customer_lng** | Option<**f64**> |  | [optional]
**customer_name** | **String** |  | 
**delivery_fee** | **i32** |  | 
**delivery_ref** | Option<**String**> |  | [optional]
**discount_amount** | **i32** |  | 
**id** | **uuid::Uuid** |  | 
**items** | Option<**serde_json::Value**> |  | 
**place_name** | Option<**String**> |  | [optional]
**status** | **String** |  | 
**subtotal** | **i32** |  | 
**total** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


