# PlanPrinter

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**brand** | Option<[**models::PrinterBrand**](PrinterBrand.md)> |  | [optional]
**connection** | **String** | `network` | `usb` | `bluetooth` | 
**host_device_id** | Option<**uuid::Uuid**> | For a USB or Bluetooth printer: the device slot it is plugged into. | [optional]
**id** | **uuid::Uuid** |  | 
**ip** | Option<**String**> |  | [optional]
**name** | **String** |  | 
**paper_mm** | **i32** |  | 
**port** | Option<**i32**> |  | [optional]
**role** | **String** | `receipt` | `kitchen` | 
**x** | **f64** |  | 
**y** | **f64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


