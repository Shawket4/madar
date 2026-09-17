# PreviewRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Price and cost as at this branch; absent = catalogue / org-level cost. | [optional]
**option_ids** | Option<**Vec<uuid::Uuid>**> | Chosen modifier options, including item-private optional-field ids. | [optional]
**quantity** | Option<**i32**> |  | [optional]
**service_mode** | Option<**String**> | `takeaway` (default) | `dine_in`. | [optional]
**size_label** | Option<**String**> | Size to price and deduct; absent = the order path's default (base price, first size's recipe). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


