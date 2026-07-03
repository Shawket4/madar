# CalibrationSummary

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**cm_in_range_pct** | Option<**f64**> | Fraction of accepted CM suggestions whose realized price landed within ±2% of the suggested price. `None` below 10 samples. | [optional]
**points_cm** | [**Vec<models::CalibrationPoint>**](CalibrationPoint.md) |  | 
**points_revenue** | [**Vec<models::CalibrationPoint>**](CalibrationPoint.md) |  | 
**revenue_in_range_pct** | Option<**f64**> |  | [optional]
**since** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


