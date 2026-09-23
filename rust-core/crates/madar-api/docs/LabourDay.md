# LabourDay

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**date** | **chrono::NaiveDate** |  | 
**labour_piastres** | **i64** | From the clock: worked minutes at each person's minute rate, plus the overtime premium. The payslip stays the final word. | 
**labour_share_bp** | Option<**i64**> | Labour as a share of sales, basis points (null with no sales). | [optional]
**sales_piastres** | **i64** | Completed sales, net of refunds. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


