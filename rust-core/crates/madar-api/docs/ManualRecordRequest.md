# ManualRecordRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**business_date** | **chrono::NaiveDate** |  | 
**check_in_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**check_out_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**notes** | Option<**String**> |  | [optional]
**reason** | **String** | Required: a hand-written attendance row always says why it exists. | 
**status** | Option<**String**> | Force a status instead of deriving one — the only way to record an `absent` or `on_leave` day by hand. | [optional]
**user_id** | **uuid::Uuid** |  | 
**work_shift_id** | Option<**uuid::Uuid**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


