# ReceiveLineInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**line_id** | **uuid::Uuid** |  | 
**quantity_received** | **f64** |  | 
**unit_cost** | Option<**i64**> | Optional ACTUAL invoice cost (piastres per purchase unit) for this delivery, when it differs from the ordered price. Drives weighted-average cost + the ledger; omitted ⟹ the PO line's ordered cost is used. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


