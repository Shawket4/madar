# DeliveryOrderInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**address_line** | Option<**String**> |  | [optional]
**branch_id** | **uuid::Uuid** |  | 
**channel** | **String** |  | 
**customer_lat** | Option<**f64**> |  | [optional]
**customer_lng** | Option<**f64**> |  | [optional]
**customer_name** | **String** |  | 
**customer_phone** | **String** |  | 
**delivery_notes** | Option<**String**> |  | [optional]
**device_token** | **String** | Device-trust token from OTP verify (proves the phone). | 
**floor** | Option<**String**> |  | [optional]
**items** | [**Vec<models::CartLineInput>**](CartLineInput.md) |  | 
**landmark** | Option<**String**> |  | [optional]
**payment_method_hint** | **String** | \"cash\" | \"card\" — a hint the teller can change at finalize. | 
**place_name** | Option<**String**> |  | [optional]
**unit_number** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


