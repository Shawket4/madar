# StaffDrink

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**allowance_at_record** | **i32** |  | 
**branch_id** | **uuid::Uuid** |  | 
**business_date** | **chrono::NaiveDate** |  | 
**comp_minor** | Option<**i32**> | What the pool comped on the sale's line, minor units, as the SERVER prices it. `null` on a record-only drink (no priced line behind it). | [optional]
**comp_minor_reported** | Option<**i32**> | What the TILL said the comp was, on a replayed sale. Differs from `comp_minor` exactly when `orders.staff_drink.record:comp_mismatch` was flagged. | [optional]
**cost_minor** | Option<**i32**> |  | [optional]
**extras_minor** | Option<**i32**> | What that line was still charged: a bigger size, extras, pricier picks. | [optional]
**id** | **uuid::Uuid** |  | 
**item_name** | **String** |  | 
**menu_item_id** | Option<**uuid::Uuid**> |  | [optional]
**note** | **String** |  | 
**order_id** | Option<**uuid::Uuid**> |  | [optional]
**overspent** | **bool** | Past the allowance, as the SERVER recounted it. | 
**overspent_on_replay** | **bool** | The server made it an overspend and the till had not. | 
**quantity** | **i32** |  | 
**recorded_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**recorded_by** | Option<**uuid::Uuid**> |  | [optional]
**size_label** | Option<**String**> |  | [optional]
**used_before** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


