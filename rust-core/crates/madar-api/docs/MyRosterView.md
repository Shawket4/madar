# MyRosterView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cant_work_days** | **Vec<i32>** |  | 
**from** | **chrono::NaiveDate** |  | 
**my_claims** | [**Vec<models::MyClaim>**](MyClaim.md) | My claims on open shifts, decided ones included: those on dates in range, and every pending one wherever it falls (SC-9, S-162). | 
**open_shifts** | [**Vec<models::OpenShift>**](OpenShift.md) | Open shifts at my branches, in published weeks (SC-9). | 
**pref_time** | Option<**String**> |  | [optional]
**prefs_set_by** | **String** | `employee` or `manager`: who set my preferences last. | 
**shifts** | [**Vec<models::RosterShift>**](RosterShift.md) | Only shifts in published weeks (SC-3). | 
**swaps** | [**Vec<models::Swap>**](Swap.md) |  | 
**team** | [**Vec<models::RosterShift>**](RosterShift.md) | Colleagues' published shifts at my branches — what a swap can be with. | 
**to** | **chrono::NaiveDate** |  | 
**unpublished_weeks** | **Vec<chrono::NaiveDate>** | Weeks in range that are not published yet at my branch. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


