# DisciplineRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**absent_days** | **i64** |  | 
**covered_by_others** | Option<**i64**> | Their own shifts a colleague covered (not rejected): the absence stays theirs (CV-6), this says someone stepped in. | [optional]
**covers_given** | Option<**i64**> | Colleagues' shifts this person covered, confirmed by a manager (CV-7). A cover is never a present day of the coverer's own. | [optional]
**covers_pending** | Option<**i64**> | Covers still waiting for the manager. | [optional]
**department_id** | Option<**uuid::Uuid**> | `None` for a person with no department set — grouped as \"Unassigned\". | [optional]
**department_name** | Option<**String**> |  | [optional]
**employee_id** | **uuid::Uuid** |  | 
**employee_name** | **String** |  | 
**late_days** | **i64** |  | 
**present_days** | **i64** |  | 
**rank_in_department** | **i64** | 1 = best in this department: fewest absences, then fewest lates, then least total late time. Ties share a rank (SQL `RANK()`), so a department where everyone has a clean record is all `1`s. | 
**total_late_minutes** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


