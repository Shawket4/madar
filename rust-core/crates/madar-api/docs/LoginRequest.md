# LoginRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Required for PIN login. The org is derived from this branch server-side. | [optional]
**email** | Option<**String**> |  | [optional]
**name** | Option<**String**> | Teller's display name (required for PIN login, unused otherwise). | [optional]
**org_id** | Option<**uuid::Uuid**> |  | [optional]
**password** | Option<**String**> |  | [optional]
**pin** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


