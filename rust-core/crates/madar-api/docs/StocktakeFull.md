# StocktakeFull

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | Option<**String**> | Branch label — only populated by the stocktakes list (so the \"All branches\" view can show which branch each stocktake belongs to). Other stocktake endpoints leave it `null`. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**finalized_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**finalized_by** | Option<**uuid::Uuid**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**note** | Option<**String**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**started_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**started_by** | **uuid::Uuid** |  | 
**started_by_name** | Option<**String**> |  | [optional]
**status** | **String** |  | 
**items** | [**Vec<models::StocktakeItem>**](StocktakeItem.md) |  | 
**variance_threshold_pct** | **f64** | Org tolerance: a counted row whose |difference| is >= this percent of the expected quantity (or that appears-from / vanishes-to zero) is flagged and requires a `variance_reason` before the count can be finalized. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


