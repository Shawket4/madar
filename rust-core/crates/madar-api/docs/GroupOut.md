# GroupOut

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**effect** | **String** | What choosing does: `none` | `adds` | `swaps`. | 
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**is_required** | **bool** |  | 
**legacy_addon_type** | Option<**String**> |  | [optional]
**max_selections** | Option<**i32**> |  | [optional]
**min_selections** | **i32** |  | 
**name** | **String** |  | 
**name_translations** | Option<**serde_json::Value**> |  | 
**options** | [**Vec<models::GroupOptionOut>**](GroupOptionOut.md) |  | 
**org_id** | **uuid::Uuid** |  | 
**selection_type** | **String** |  | 
**sort** | **i32** |  | 
**swap_category_id** | Option<**uuid::Uuid**> | For `swaps`: the ingredient category whose recipe line each option replaces. | [optional]
**swap_category_slug** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


