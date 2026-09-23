# RosterView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**date_sets** | Option<[**Vec<models::DateSet>**](DateSet.md)> | The dates that hold their own set (a date change), a day off included: the ones \"back to the pattern\" applies to. | [optional]
**from** | **chrono::NaiveDate** |  | 
**holidays** | [**Vec<models::HolidayView>**](HolidayView.md) |  | 
**limits_unconfirmed** | **bool** | The limits are not yet confirmed by a lawyer; say so beside them. | 
**open_shifts** | [**Vec<models::OpenShift>**](OpenShift.md) |  | 
**published_weeks** | **Vec<chrono::NaiveDate>** | Saturdays of the published weeks in range. | 
**shifts** | [**Vec<models::RosterShift>**](RosterShift.md) |  | 
**staff** | [**Vec<models::RosterPerson>**](RosterPerson.md) |  | 
**to** | **chrono::NaiveDate** |  | 
**warnings** | [**Vec<models::LabourWarning>**](LabourWarning.md) | Labour limits the roster (or, for `overtime_day`, the clock) goes past. Warnings, never blocks (RU-13). | 
**work_shifts** | [**Vec<models::WorkShiftBrief>**](WorkShiftBrief.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


