# PublicCreateBookingRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**customer_name** | **String** |  | 
**customer_phone** | **String** |  | 
**device_token** | **String** | Device-trust token from the delivery OTP flow, proving this phone is verified. | 
**kind** | Option<**String**> | `reservation` or `walk_in`; defaults from whether `reserved_for` is set. | [optional]
**lat** | Option<**f64**> |  | [optional]
**lng** | Option<**f64**> |  | [optional]
**party_size** | Option<**i32**> |  | [optional]
**reserved_for** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


