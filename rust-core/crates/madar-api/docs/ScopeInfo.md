# ScopeInfo

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**all_branches** | **bool** | True when the answer spans EVERY branch the caller can access. | 
**branches** | **Vec<String>** | The branch names the answer covers. | 
**label** | **String** | Human-readable label, e.g. \"All branches (3)\" or \"Sidi Henish\". | 
**unmatched_branch** | Option<**String**> | Set when the user named a branch that couldn't be matched; the answer then falls back to all accessible branches and this flags the mismatch. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


