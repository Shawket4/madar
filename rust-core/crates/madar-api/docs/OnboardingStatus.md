# OnboardingStatus

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**can_complete** | **bool** | True when every `required` step is done (the Finish button enabler). | 
**completed** | **bool** | Derived terminal flag (`completed_at IS NOT NULL`) — the dashboard routes into the wizard while this is false. | 
**completed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**recipe_coverage** | **f64** | Recipe coverage across active menu items (0..1) — drives the cost engine; surfaced separately because it's a percentage, not a bool. | 
**steps** | [**Vec<models::OnboardingStep>**](OnboardingStep.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


