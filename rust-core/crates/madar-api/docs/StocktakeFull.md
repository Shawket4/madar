# StocktakeFull

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | Option<**String**> | Branch label — only populated by the stocktakes list (so the \"All branches\" view can show which branch each stocktake belongs to). | [optional]
**counted_items** | Option<**i64**> | Items counted / items in scope; populated by the list endpoint only. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**finalized_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**finalized_by** | Option<**uuid::Uuid**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**note** | Option<**String**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**scope** | **serde_json::Value** | `{\"kind\":\"full\"}`, `{\"kind\":\"category\",\"category_id\":…}` or `{\"kind\":\"items\",\"org_ingredient_ids\":[…]}`. | 
**started_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**started_by** | **uuid::Uuid** |  | 
**started_by_name** | Option<**String**> |  | [optional]
**status** | **String** |  | 
**total_items** | Option<**i64**> |  | [optional]
**items** | [**Vec<models::StocktakeItem>**](StocktakeItem.md) |  | 
**variance_threshold_pct** | **f64** | Org tolerance: a counted row whose |difference| is >= this percent of book stock (or that appears-from / vanishes-to zero) is flagged and requires a `variance_reason` before the count can be finalized. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


