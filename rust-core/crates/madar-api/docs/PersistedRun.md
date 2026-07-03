# PersistedRun

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**completed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**config** | [**models::AnalysisConfig**](AnalysisConfig.md) |  | 
**error_message** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**mode_summary** | [**models::ModeSummary**](ModeSummary.md) |  | 
**org_id** | **uuid::Uuid** |  | 
**started_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**status** | [**models::RunStatus**](RunStatus.md) |  | 
**window_days** | **f64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


