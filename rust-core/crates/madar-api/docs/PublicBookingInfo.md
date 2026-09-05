# PublicBookingInfo

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**blackout_dates** | **Vec<String>** |  | 
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**default_duration_minutes** | **i32** |  | 
**enabled** | **bool** |  | 
**horizon_days** | **i32** |  | 
**hours** | [**Vec<models::HoursEntry>**](HoursEntry.md) |  | 
**lead_time_minutes** | **i32** |  | 
**max_party** | **i32** |  | 
**min_party** | **i32** |  | 
**org_name** | **String** |  | 
**require_otp** | **bool** |  | 
**slot_minutes** | **i32** |  | 
**timezone** | **String** |  | 
**today** | **String** | Today's service date in the branch zone (the picker's floor). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


