# BranchPlanView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**categories** | [**Vec<models::PlanCategory>**](PlanCategory.md) |  | 
**devices** | [**Vec<models::PlanRegisteredDevice>**](PlanRegisteredDevice.md) |  | 
**item_overrides** | [**Vec<models::SectionCount>**](SectionCount.md) | Items routed to a section one by one, bypassing their category. | 
**open_items** | [**Vec<models::SectionCount>**](SectionCount.md) | Kitchen items not yet bumped, per section. A section with any can't be removed (spec KS-9, CH-4). | 
**plan** | [**models::BranchPlan**](BranchPlan.md) |  | 
**routing_mode** | **String** | The branch's kitchen routing mode as stored now. | 
**saved** | **bool** | False until the plan is first saved. Until then it is assembled from the branch's existing stations, printers and registered devices. | 
**version** | **i32** | Bumped by every save; send it back as `expected_version`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


