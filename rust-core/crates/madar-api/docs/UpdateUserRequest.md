# UpdateUserRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**email** | Option<**String**> |  | [optional]
**is_active** | Option<**bool**> |  | [optional]
**name** | Option<**String**> |  | [optional]
**password** | Option<**String**> | Plain-text new password. Server-side bcrypt-hashed. | [optional]
**phone** | Option<**String**> |  | [optional]
**pin** | Option<**String**> |  | [optional]
**role** | Option<[**models::UserRole**](UserRole.md)> | Only org-admins and above can change roles. Promoting to `super_admin` requires the caller to be a super-admin. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


