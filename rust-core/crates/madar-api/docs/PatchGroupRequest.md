# PatchGroupRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**effect** | Option<**String**> | `none` | `adds` | `swaps`. Changing it re-derives `legacy_addon_type` for old tills: swaps milk → `milk_type`, swaps coffee_bean → `coffee_type`; otherwise the provided/existing type (a magic type on a non-swap group becomes `extra`). | [optional]
**is_active** | Option<**bool**> | Reactivate (`true`) or deactivate (`false`) the group. | [optional]
**is_required** | Option<**bool**> |  | [optional]
**legacy_addon_type** | Option<**String**> | Absent = keep; `null` = clear (group invisible to old tills); a string = set. | [optional]
**max_selections** | Option<**i32**> | Absent = keep; `null` = no upper bound; a number = set. | [optional]
**min_selections** | Option<**i32**> |  | [optional]
**name** | Option<**String**> |  | [optional]
**name_translations** | Option<**serde_json::Value**> |  | [optional]
**selection_type** | Option<**String**> |  | [optional]
**sort** | Option<**i32**> |  | [optional]
**swap_category_id** | Option<**uuid::Uuid**> | Absent = keep; `null` = clear; a category id of this org = set. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


