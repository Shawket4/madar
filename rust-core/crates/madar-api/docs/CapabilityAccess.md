# CapabilityAccess

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**capability** | **String** |  | 
**editable** | **bool** | Can the caller change this row for this person? | 
**effective** | **bool** | Held here after everything. | 
**from_roles** | **Vec<String>** | Role names granting it (for \"Inherits from …\"). | 
**limits** | Option<[**models::LimitsView**](LimitsView.md)> |  | [optional]
**overrides** | [**Vec<models::OverrideView>**](OverrideView.md) |  | 
**source** | **String** | Where the answer comes from: owner | core | allow | deny | role | none. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


