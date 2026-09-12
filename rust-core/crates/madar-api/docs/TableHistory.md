# TableHistory

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**average_bill_minor** | **i64** | Mean spend per settled bill, minor units. | 
**average_minutes** | **i64** | Mean minutes a party occupied the table, over settled bills — the number that says whether a table turns. | 
**covers** | **i64** | Settled bills only. | 
**from** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**label** | **String** |  | 
**settled_count** | **i64** |  | 
**sittings** | [**Vec<models::TableSitting>**](TableSitting.md) | Bills opened on this table in the window, newest first. | 
**table_id** | **uuid::Uuid** |  | 
**to** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**total_minor** | **i64** |  | 
**turns_per_day_x100** | **i64** | Settled bills per day over the window, x100 so the wire stays integer. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


