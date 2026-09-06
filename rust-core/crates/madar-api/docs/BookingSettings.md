# BookingSettings

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**auto_no_show_minutes** | Option<**i32**> | Unseated this long after `starts_at` → `no_show` automatically. `null` = only when the window ends. | [optional]
**blackout_dates** | **Vec<String>** | ISO dates (`YYYY-MM-DD`) with no online slots. | 
**branch_id** | **uuid::Uuid** |  | 
**default_duration_minutes** | **i32** |  | 
**enabled** | **bool** | Online (public) booking switch. Host bookings work regardless. | 
**hold_minutes** | **i32** | The floor shows the table as held from `starts_at - hold_minutes`. | 
**horizon_days** | **i32** |  | 
**hours** | [**Vec<models::HoursEntry>**](HoursEntry.md) |  | 
**lead_time_minutes** | **i32** |  | 
**max_covers_per_slot** | Option<**i32**> | Optional ceiling on guests whose bookings start in one slot. | [optional]
**max_party** | **i32** |  | 
**min_party** | **i32** |  | 
**reminder_lead_minutes** | Option<**i32**> | WhatsApp reminder lead. `null` = no reminder. | [optional]
**require_otp** | **bool** | Online guests must verify their phone by WhatsApp code. | 
**slot_minutes** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


