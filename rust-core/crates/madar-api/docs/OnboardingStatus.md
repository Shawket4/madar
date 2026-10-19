# OnboardingStatus

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**can_complete** | **bool** |  | 
**completed** | **bool** | Always true: old builds never open their wizard. | 
**completed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**recipe_coverage** | **f64** |  | 
**steps** | [**Vec<models::OnboardingStep>**](OnboardingStep.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


