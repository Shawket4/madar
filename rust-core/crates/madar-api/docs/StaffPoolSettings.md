# StaffPoolSettings

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | `null` = the org-wide default. A branch id = that branch's override. | [optional]
**daily_allowance** | Option<**i32**> | Staff drinks this branch may give in one business day. | [optional]
**eligible_item_ids** | Option<**Vec<uuid::Uuid>**> | The menu items that count. EMPTY = the pool is off. | [optional]
**enabled** | Option<**bool**> | The owner's master switch for this scope. | [optional]
**org_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


