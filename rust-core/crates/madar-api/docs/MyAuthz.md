# MyAuthz

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**ask_manager** | **Vec<String>** | Capabilities not held that show \"ask a manager\" instead of nothing. | 
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**capabilities** | **Vec<String>** | Capability keys held. | 
**epoch** | **i64** |  | 
**limits** | [**std::collections::HashMap<String, models::LimitsView>**](LimitsView.md) | Limits on held capabilities, by key; absent = unlimited. | 
**owner** | **bool** |  | 
**platform** | **bool** |  | 
**role_kinds** | **Vec<String>** | Role kinds held here (org_admin, branch_manager, teller, waiter, kitchen). | 
**spec_version** | **u32** |  | 
**user_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


