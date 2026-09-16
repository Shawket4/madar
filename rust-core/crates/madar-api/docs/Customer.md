# Customer

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**last_order_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**loyalty_customer_id** | Option<**uuid::Uuid**> |  | [optional]
**name** | **String** |  | 
**notes** | Option<**String**> |  | [optional]
**orders_count** | **i64** |  | 
**phone** | Option<**String**> |  | [optional]
**total_spent** | **i64** | Sum of completed sales, minor units. | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


