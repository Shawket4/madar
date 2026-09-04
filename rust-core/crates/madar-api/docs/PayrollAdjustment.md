# PayrollAdjustment

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_piastres** | Option<**i64**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**effective_date** | **chrono::NaiveDate** |  | 
**id** | **uuid::Uuid** |  | 
**org_id** | **uuid::Uuid** |  | 
**original_amount_piastres** | Option<**i64**> | What the RULE computed, before any human touched it. `None` on a hand-entered row — nothing was overridden, so there is no \"original\". | [optional]
**overridden_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**override_reason** | Option<**String**> |  | [optional]
**percent_of_base** | Option<**f64**> |  | [optional]
**reason** | **String** |  | 
**source** | **String** |  | 
**status** | **String** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**user_id** | **uuid::Uuid** |  | 
**user_name** | Option<**String**> |  | [optional]
**waive_reason** | Option<**String**> |  | [optional]
**waived_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | A waived deduction keeps its amount and stays visible; payroll skips it. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


