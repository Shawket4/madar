# ApplyPackagingRulesResult

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**catalog_revision** | **i64** |  | 
**sizes_changed** | **i64** | Sizes (incl. linked copies) whose stored lines changed. | 
**sizes_seen** | **i64** | Sizes examined (every size of every live item in the org). | 
**sizes_with_manual_packaging** | **i64** | Sizes that still have an OWN line in a packaging category: typed by hand, they are kept (and win over a rule for the same ingredient) — review them. | 
**sizes_with_rule** | **i64** | Sizes that now carry at least one rule line. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


