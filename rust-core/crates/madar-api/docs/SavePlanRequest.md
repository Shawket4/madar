# SavePlanRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**expected_version** | **i32** | The `version` the plan was loaded at. A save over a newer version is refused (`PLAN_CHANGED`), so two people editing one branch never silently overwrite each other. | 
**plan** | [**models::BranchPlan**](BranchPlan.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


