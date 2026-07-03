# CreateBookingRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**customer_name** | **String** |  | 
**customer_phone** | **String** |  | 
**kind** | Option<**String**> | `reservation` or `walk_in`. Defaults from whether `reserved_for` is set. | [optional]
**notes** | Option<**String**> |  | [optional]
**party_size** | Option<**i32**> |  | [optional]
**quoted_ready_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**reserved_for** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


