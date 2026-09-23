# StaffSession

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**device_token** | Option<**String**> | Kept in the phone's secure storage and sent as `X-Staff-Device` on every call (RO-3). It is what refreshes the session. | [optional]
**employee_id** | Option<**uuid::Uuid**> | Who signed in: the employee. | [optional]
**name** | Option<**String**> |  | [optional]
**needs_org** | **bool** | Set when the number works at more than one business and none was picked: ask, then verify again with `org_id`. The code stays valid. | 
**new_phone** | **bool** | True when this sign-in moved the account from another phone. | 
**org_id** | Option<**uuid::Uuid**> |  | [optional]
**orgs** | [**Vec<models::StaffOrgChoice>**](StaffOrgChoice.md) |  | 
**role** | Option<[**models::UserRole**](UserRole.md)> | The linked account's role; null for an employee with no account. | [optional]
**token** | Option<**String**> | The staff token: `Authorization: Bearer` on `/staff/_*` only. It lives an hour; refresh it with `POST /auth/staff/refresh`. | [optional]
**token_expires_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**user_id** | Option<**uuid::Uuid**> | Their Madar account when they have one (a manager, a cashier). Manager acts in the app go through it. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


