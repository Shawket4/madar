# AdjustRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**customer_id** | **uuid::Uuid** |  | 
**note** | Option<**String**> |  | [optional]
**points** | **i32** | Signed. Negative takes points away. | 
**track** | Option<**u32**> | The stamp track (2–4) to adjust; absent = track 1 (the balance above). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


