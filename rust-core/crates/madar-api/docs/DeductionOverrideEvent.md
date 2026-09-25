# DeductionOverrideEvent

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**action** | **String** | `waive` · `unwaive` · `override` | 
**actor_id** | Option<**uuid::Uuid**> |  | [optional]
**actor_name** | Option<**String**> |  | [optional]
**amount_after_piastres** | Option<**i64**> |  | [optional]
**amount_before_piastres** | Option<**i64**> | What the line charged before and after this event (a waiver: after 0; undoing one: before 0). | [optional]
**at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**deduction_id** | **uuid::Uuid** |  | 
**effective_date** | Option<**chrono::NaiveDate**> | The line itself: its day, what made it (`absence`, `late_penalty`, …) and its rule's reason code. Null if the line is gone. | [optional]
**employee_id** | Option<**uuid::Uuid**> |  | [optional]
**employee_name** | Option<**String**> |  | [optional]
**reason** | Option<**String**> |  | [optional]
**reason_code** | Option<**String**> |  | [optional]
**source** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


