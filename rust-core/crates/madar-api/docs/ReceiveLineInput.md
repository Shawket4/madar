# ReceiveLineInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**line_cost** | Option<**i64**> | Optional ACTUAL invoice total (piastres) for what this delivery brought, when it differs from the ordered price. Preferred over `unit_cost`. Drives weighted-average cost + the ledger; omitted (with `unit_cost`) ⟹ the ordered line total, pro rata to the quantity received. | [optional]
**line_id** | **uuid::Uuid** |  | 
**quantity_received** | **f64** |  | 
**unit_cost** | Option<**i64**> | Optional ACTUAL invoice cost in piastres per purchase unit (older clients). Ignored when `line_cost` is sent. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


