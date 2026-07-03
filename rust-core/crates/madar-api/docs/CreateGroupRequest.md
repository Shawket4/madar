# CreateGroupRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**is_required** | Option<**bool**> |  | [optional]
**legacy_addon_type** | Option<**String**> | The legacy addon type this group is presented as to OLD clients through the compat shim (the managed addon-type dropdown, e.g. `milk_type` / `coffee_type` / `extra`). Swap-family behavior keys on it. `null` = a custom group with no legacy lineage — INVISIBLE to old clients (the shim projects `type` from this value, and the old wire requires it), so set it whenever the pre-teardown fleet must see the group's options. | [optional]
**max_selections** | Option<**i32**> |  | [optional]
**min_selections** | Option<**i32**> |  | [optional]
**name** | **String** |  | 
**name_translations** | Option<**serde_json::Value**> |  | [optional]
**selection_type** | **String** | 'single' | 'multi'. | 
**sort** | Option<**i32**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


