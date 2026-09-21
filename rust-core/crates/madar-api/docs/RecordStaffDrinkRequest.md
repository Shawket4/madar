# RecordStaffDrinkRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**allowance_at_record** | Option<**i32**> | What the DEVICE believed the pool stood at. Kept for the owner to compare against what the server recomputed; never trusted. | [optional]
**branch_id** | **uuid::Uuid** |  | 
**cost_minor** | Option<**i32**> |  | [optional]
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**id** | **uuid::Uuid** | Client-minted, and the idempotency key: replaying the same drink twice is the same row, not a second one off the allowance. | 
**item_name** | Option<**String**> | Frozen at the till, so a later rename never rewrites history. | [optional]
**menu_item_id** | **uuid::Uuid** |  | 
**note** | **String** | REQUIRED. Who the drink is for and why, in the teller's own words. | 
**order_id** | Option<**uuid::Uuid**> | The zero-priced sale this drink rang as, when there is one. | [optional]
**overspent** | Option<**bool**> |  | [optional]
**quantity** | Option<**i32**> |  | [optional]
**recorded_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the teller rang it. Defaults to now; the business day is derived from this in the BRANCH's timezone, never from the server's clock date. | [optional]
**size_label** | Option<**String**> |  | [optional]
**till_id** | Option<**uuid::Uuid**> |  | [optional]
**used_before** | Option<**i32**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


