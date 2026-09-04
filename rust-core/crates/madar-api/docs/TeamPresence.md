# TeamPresence

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**absent** | **i64** |  | 
**business_date** | **chrono::NaiveDate** | The branch's business date, in ITS timezone — not the manager's device. | 
**late** | **i64** |  | 
**on_leave** | **i64** |  | 
**planned_minutes** | **i64** | Minutes rostered for today across the team. | 
**present** | **i64** |  | 
**rows** | [**Vec<models::PresenceRow>**](PresenceRow.md) |  | 
**worked_minutes** | **i64** | Minutes actually worked so far today across the team. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


