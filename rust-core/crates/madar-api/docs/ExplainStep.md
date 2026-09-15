# ExplainStep

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**applies_here** | Option<**bool**> | For an assignment step: does the assignment cover the branch asked about? | [optional]
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**detail** | Option<**String**> |  | [optional]
**grants** | Option<**bool**> | For an assignment step: does the role grant the capability? | [optional]
**kind** | **String** | owner | inactive | assignment | core | override_allow | override_deny | protected | not_held | limit | ask_manager | 
**role_name** | Option<**String**> |  | [optional]
**role_name_ar** | Option<**String**> | The role's Arabic name, beside `role_name`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


