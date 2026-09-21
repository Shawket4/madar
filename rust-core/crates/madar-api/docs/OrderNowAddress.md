# OrderNowAddress

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**address_line** | Option<**String**> |  | [optional]
**branch_id** | Option<**uuid::Uuid**> | The branch it was last ordered from. | [optional]
**channel** | **String** | The channel it was last used with: `in_mall`, `outside` or `umbrella`. | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**customer_id** | **uuid::Uuid** |  | 
**delivery_notes** | Option<**String**> |  | [optional]
**delivery_zone_id** | Option<**uuid::Uuid**> |  | [optional]
**floor** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**label** | Option<**String**> |  | [optional]
**landmark** | Option<**String**> |  | [optional]
**last_used_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**lat** | Option<**f64**> |  | [optional]
**lng** | Option<**f64**> |  | [optional]
**place_name** | Option<**String**> |  | [optional]
**unit_number** | Option<**String**> |  | [optional]
**use_count** | **i32** |  | 
**stale** | **bool** | True when it can no longer be delivered to from the last branch. | 
**stale_reason** | Option<**String**> | `out_of_zone` | `zone_unavailable` | `branch_unavailable`. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


