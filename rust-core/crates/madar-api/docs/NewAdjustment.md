# NewAdjustment

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_piastres** | Option<**i64**> |  | [optional]
**effective_date** | Option<**chrono::NaiveDate**> | The month it lands in (AD-1): any day of that month; the first month of a recurring line (AD-3). Defaults to today. Must be an open month. | [optional]
**employee_id** | **uuid::Uuid** |  | 
**kind** | **String** | `bonus` · `deduction` | 
**percent_of_base** | Option<**f64**> | A bonus may be a % of salary. | [optional]
**reason** | **String** |  | 
**recurring** | Option<**bool**> | Every month until stopped (AD-3). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


