# OpenTicketItemView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | 
**line** | Option<**serde_json::Value**> | The frozen priced SnapshotLine (name, size, addons, totals). | 
**line_total** | **i32** |  | 
**menu_item_id** | Option<**uuid::Uuid**> |  | [optional]
**round_fired_at** | **chrono::DateTime<chrono::FixedOffset>** | When the round this line came in on was fired. A bill is read as a sequence of visits to the table — \"the drinks at seven, the food at half past\" — and without the clock a till can only show a flat list that says nothing about how the evening went. | 
**round_number** | **i32** |  | 
**voided** | **bool** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


