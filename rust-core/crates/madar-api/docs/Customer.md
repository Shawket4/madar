# Customer

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**birth_day** | Option<**i32**> |  | [optional]
**birth_month** | Option<**i32**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**is_member** | Option<**bool**> | A live loyalty membership exists for this customer (same id). | [optional]
**last_order_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**locale** | Option<**String**> | `en` or `ar`; null when never asked. | [optional]
**loyalty_customer_id** | Option<**uuid::Uuid**> | DEPRECATED, kept for one release: a loyalty membership now shares the customer's id, so this is `id` when `is_member` and null otherwise. | [optional]
**marketing_opt_out** | Option<**bool**> |  | [optional]
**name** | **String** |  | 
**notes** | Option<**String**> |  | [optional]
**orders_count** | **i64** |  | 
**phone** | Option<**String**> |  | [optional]
**points_balance** | Option<**i32**> | Null when not a member. | [optional]
**source** | Option<**String**> | Where the customer first came from: `pos`, `online`, `loyalty`, `booking`, `table_qr`, `aggregator` or `dashboard`. | [optional]
**total_spent** | **i64** | Sum of completed sales, minor units. | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**visits_balance** | Option<**i32**> | Null when not a member. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


