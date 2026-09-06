# ScopeInfo

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**all_branches** | **bool** | True when the answer spans every branch the caller can access. | 
**branches** | **Vec<String>** |  | 
**label** | **String** | Human-readable label, e.g. \"All branches (3)\" or \"Sidi Henish\". | 
**unmatched_branch** | Option<**String**> | Set when a branch was named but could not be matched. The answer then falls back to the full accessible set, and this flags the mismatch rather than silently answering a different question. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


