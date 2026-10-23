# PlanState

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addons** | Option<**Vec<String>**> | Active add-on keys (Rewards by Madar: `[\"loyalty\"]`), already inside `entitlements.features`. | [optional]
**branch_limit** | Option<**u32**> | The plan's branch limit, `null` for unlimited. | [optional]
**branches** | [**Vec<models::PlanBranch>**](PlanBranch.md) |  | 
**entitlements** | **serde_json::Value** | What the plan allows: `{features: [..], limits: {branches, pos_devices_per_branch, kds_devices, waiter_devices}, realtime}` (madar-plan's `Entitlements`). A limit that is `null` is unlimited. | 
**inactive_tills** | **i64** | POS tills the plan has switched off. | 
**live_branches** | **i64** | Live selling branches (not deleted, not warehouses). | 
**org_id** | **uuid::Uuid** |  | 
**over_branch_limit** | **bool** | Past the plan's branch limit (a downgraded org keeps all its branches and cannot add one). | 
**plan** | **String** | `free` | `paid`. | 
**signup_source** | **String** | `admin` | `self`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


