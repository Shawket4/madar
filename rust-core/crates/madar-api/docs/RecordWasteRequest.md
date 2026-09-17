# RecordWasteRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**device_id** | Option<**uuid::Uuid**> |  | [optional]
**id** | **uuid::Uuid** | Client-minted; the idempotency key. | 
**live_approval** | Option<[**models::ReplayApproval**](ReplayApproval.md)> | A manager's one-time PIN approval for the LIVE route (owner, 2026-09-17), over the person's `max_value` limit. Additive. | [optional]
**note** | Option<**String**> |  | [optional]
**occurred_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When it happened on the device. Default: now. | [optional]
**quantity** | **f64** | In `unit`. Whole units for a menu item. | 
**reason** | **String** | expired | spoiled | damaged | overproduction | theft | other | 
**size_label** | Option<**String**> | Menu items only: the size whose recipe is wasted (default: the first size). | [optional]
**subject_id** | **uuid::Uuid** | An org ingredient id, or a menu item id. | 
**subject_kind** | **String** | `ingredient` | `menu_item` | 
**till_id** | Option<**uuid::Uuid**> |  | [optional]
**unit** | Option<**String**> | `g` | `kg` | `ml` | `l` | `pcs`. Default: the ingredient's own unit; a menu item is always `pcs`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


