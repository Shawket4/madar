# StaffSession

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**device_token** | Option<**String**> | Kept in the phone's secure storage and sent as `X-Staff-Device` on every punch and ping (RO-3). | [optional]
**name** | Option<**String**> |  | [optional]
**needs_org** | **bool** | Set when the number works at more than one business and none was picked: ask, then verify again with `org_id`. The code stays valid. | 
**new_phone** | **bool** | True when this sign-in moved the account from another phone. | 
**org_id** | Option<**uuid::Uuid**> |  | [optional]
**orgs** | [**Vec<models::StaffOrgChoice>**](StaffOrgChoice.md) |  | 
**role** | Option<[**models::UserRole**](UserRole.md)> |  | [optional]
**token** | Option<**String**> | `Authorization: Bearer` for every other call. | [optional]
**user_id** | Option<**uuid::Uuid**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


