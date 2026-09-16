# UserAccess

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**assignments** | [**Vec<models::AssignmentView>**](AssignmentView.md) |  | 
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**can_edit** | **bool** | Can the caller edit this person's access at all? | 
**capabilities** | [**Vec<models::CapabilityAccess>**](CapabilityAccess.md) |  | 
**is_owner** | **bool** |  | 
**locked_reason** | Option<**String**> | Why not, when not (self | owner | not_dominant | not_above | missing_authority). | [optional]
**name** | **String** |  | 
**user_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


