# LoginRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Required for PIN login. The org is derived from this branch server-side. | [optional]
**email** | Option<**String**> |  | [optional]
**name** | Option<**String**> | The person's display name. Optional for PIN login: without it the PIN alone identifies the person (PIN-only sign-in, org-wide unique PINs). Old tablets send it and keep the name-narrowed lookup. | [optional]
**org_id** | Option<**uuid::Uuid**> |  | [optional]
**password** | Option<**String**> |  | [optional]
**pin** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


