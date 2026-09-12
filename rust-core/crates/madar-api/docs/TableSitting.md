# TableSitting

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**closed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the bill was settled or voided; `None` while it is still open. | [optional]
**customer_name** | Option<**String**> |  | [optional]
**guest_count** | Option<**i32**> |  | [optional]
**minutes** | **i64** | Minutes between the two, or to now while the bill is still open. | 
**open_ticket_id** | **uuid::Uuid** |  | 
**opened_at** | **chrono::DateTime<chrono::FixedOffset>** | When the party's bill was opened — the closest thing the server has to when they sat down. | 
**order_id** | Option<**uuid::Uuid**> | The settled sale, when the bill became one. | [optional]
**order_number** | Option<**i32**> |  | [optional]
**status** | **String** |  | 
**ticket_ref** | Option<**String**> |  | [optional]
**total_amount** | Option<**i32**> | What the sale came to, in minor units. `None` for an unsettled or voided bill — a table's takings only count money that was taken. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


