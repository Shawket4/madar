# TableSitting

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**closed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the bill was settled or voided; `None` while it is still open. | [optional]
**customer_id** | Option<**uuid::Uuid**> | The customer the sitting belongs to, when one is known: the sale's once settled (a settle may name one the bill never had), else the bill's. Read through the merge chain, so it is always a live customer. | [optional]
**customer_name** | Option<**String**> |  | [optional]
**guest_count** | Option<**i32**> |  | [optional]
**minutes** | **i64** | Minutes from `seated_at` to the close, or to now while still open. | 
**open_ticket_id** | **uuid::Uuid** |  | 
**opened_at** | **chrono::DateTime<chrono::FixedOffset>** | When the party's bill was opened — the closest thing the server has to when they sat down. | 
**order_id** | Option<**uuid::Uuid**> | The settled sale, when the bill became one. | [optional]
**order_number** | Option<**i32**> |  | [optional]
**seated_at** | **chrono::DateTime<chrono::FixedOffset>** | When the party sat down: the seat hold's stamp when they were seated before ordering, else the bill's opening. | 
**status** | **String** |  | 
**ticket_ref** | Option<**String**> |  | [optional]
**total_amount** | Option<**i32**> | What the sale came to, in minor units. `None` for an unsettled or voided bill — a table's takings only count money that was taken. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


