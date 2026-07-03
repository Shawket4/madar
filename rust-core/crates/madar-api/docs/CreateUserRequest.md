# CreateUserRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_ids** | Option<**Vec<uuid::Uuid>**> | Branches to assign the new user to immediately. Branch managers can only assign to branches they themselves are assigned to. | [optional]
**email** | Option<**String**> | Required for admins and managers; ignored for tellers. | [optional]
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**password** | Option<**String**> | Required when `role` is anything other than `teller`. Plain text; hashed server-side with bcrypt before storage. | [optional]
**phone** | Option<**String**> |  | [optional]
**pin** | Option<**String**> | Required when `role = teller`. 4–6 ASCII digits. | [optional]
**role** | [**models::UserRole**](UserRole.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


