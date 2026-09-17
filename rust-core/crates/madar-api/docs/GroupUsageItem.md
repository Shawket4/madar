# GroupUsageItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**category_name** | Option<**String**> |  | [optional]
**default_option_id** | Option<**uuid::Uuid**> | Swap groups only: the option preselected on this item, i.e. the first offered option (sort, name) carrying the recipe's ingredient of the swap category, on the item's first size that has one. `null` for non-swap groups or when the recipe's ingredient is not offered (lint F4 / F5). | [optional]
**included_option_count** | **i32** | Active options this item offers. | 
**included_option_ids** | Option<**Vec<uuid::Uuid>**> | `null` = the item offers every option of the group. | [optional]
**is_required** | **bool** | Effective for this item: attachment override, else the group default. | 
**item_id** | **uuid::Uuid** |  | 
**item_is_active** | **bool** |  | 
**item_name** | **String** |  | 
**legacy_origin** | Option<**String**> | `slot` | `allowlist` | `options` (old-till provenance). | [optional]
**max_selections** | Option<**i32**> |  | [optional]
**min_selections** | **i32** |  | 
**warnings** | [**Vec<models::LintIssue>**](LintIssue.md) | Lint findings F4–F10 about this item and this group. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


