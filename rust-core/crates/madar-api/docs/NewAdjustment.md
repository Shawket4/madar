# NewAdjustment

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_piastres** | Option<**i64**> |  | [optional]
**effective_date** | Option<**chrono::NaiveDate**> |  | [optional]
**kind** | **String** | `bonus` · `deduction` | 
**percent_of_base** | Option<**f64**> | A bonus may be a % of salary. | [optional]
**reason** | **String** |  | 
**recurring** | Option<**bool**> | Every month until stopped (AD-3). | [optional]
**user_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


