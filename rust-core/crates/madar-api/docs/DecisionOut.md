# DecisionOut

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**action** | **String** |  | 
**baseline** | **serde_json::Value** |  | 
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**detail** | **serde_json::Value** |  | 
**id** | **uuid::Uuid** |  | 
**impact** | **serde_json::Value** | Measured after-window aggregate; `null` until ≥1 day of after-data. | 
**impact_complete** | **bool** | True once the full baseline window has elapsed since the decision. | 
**item_name** | **String** |  | 
**menu_item_id** | **uuid::Uuid** |  | 
**signal_kind** | **String** |  | 
**size_label** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


