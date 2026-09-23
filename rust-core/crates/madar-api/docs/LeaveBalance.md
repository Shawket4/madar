# LeaveBalance

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**carried_over_days** | **f64** |  | 
**employee_id** | **uuid::Uuid** |  | 
**entitled_days** | **f64** |  | 
**id** | **uuid::Uuid** |  | 
**leave_type_id** | **uuid::Uuid** |  | 
**leave_type_name** | Option<**String**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**remaining_days** | **f64** | `entitled + carried_over − used`. Computed, not stored. | 
**used_days** | **f64** |  | 
**year** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


