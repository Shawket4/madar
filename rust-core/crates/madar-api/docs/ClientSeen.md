# ClientSeen

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**app_version** | Option<**String**> | From an `X-Madar-Client` of the form `<app>/<semver>` only; `null` for the dashboard and for any client identified by its User-Agent. | [optional]
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**branch_name** | Option<**String**> |  | [optional]
**client** | Option<**String**> | `X-Madar-Client`; else `dashboard` for a browser; else the User-Agent. | [optional]
**device_code** | Option<**String**> | The registered device's code, when the device is registered. | [optional]
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**first_seen_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**last_legacy_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**last_legacy_kind** | Option<**String**> | The latest legacy path kind (`legacy_shifts_route`, `replay_shift_id_field`, …). | [optional]
**last_legacy_path** | Option<**String**> |  | [optional]
**last_seen_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**legacy_kinds** | **Vec<String>** | Every legacy kind this client has hit. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


