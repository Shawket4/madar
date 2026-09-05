# PublicBookingInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**device_token** | Option<**String**> | From `/public/otp/verify`; required when the branch requires OTP. | [optional]
**guest_name** | **String** |  | 
**locale** | Option<**String**> |  | [optional]
**notes** | Option<**String**> |  | [optional]
**party_size** | **i32** |  | 
**phone** | **String** |  | 
**starts_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


