# EarningItemList

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**inherited** | **bool** | True when these rows are the org's rather than this branch's own. | 
**items** | [**Vec<models::EarningItem>**](EarningItem.md) | Empty means EVERY item collects — not that nothing does. | 
**org_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


