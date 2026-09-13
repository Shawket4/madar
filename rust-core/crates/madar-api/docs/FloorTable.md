# FloorTable

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**height** | **f64** |  | 
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**label** | **String** |  | 
**next_booking** | Option<[**models::TableBookingHint**](TableBookingHint.md)> | The next active booking claiming this table (today's service, or the one in progress). The floor renders \"held\" from `held_from` by its own clock; nothing here is written to `status`. Only the list endpoint fills it — single-row writes return `null`. | [optional]
**org_id** | **uuid::Uuid** |  | 
**party_size** | Option<**i32**> | How many sat down (covers) on the live occupancy, when the host counted them or the bill carries a guest count. `null` when free or unknown. | [optional]
**pos_x** | **f64** |  | 
**pos_y** | **f64** |  | 
**rotation** | **f64** |  | 
**seated_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the party at this table sat down — the hold's stamp, else the bill's opening. `null` unless the table is seated. Every device renders its table clock from this, so they all agree. | [optional]
**seats** | **i32** |  | 
**section_id** | Option<**uuid::Uuid**> |  | [optional]
**shape** | **String** |  | 
**status** | **String** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**width** | **f64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


