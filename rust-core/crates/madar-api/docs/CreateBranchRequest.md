# CreateBranchRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**address** | Option<**String**> |  | [optional]
**geo_radius_meters** | Option<**i32**> | Geofence radius in meters. Defaults to 200. | [optional]
**latitude** | Option<**f64**> |  | [optional]
**longitude** | Option<**f64**> |  | [optional]
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**phone** | Option<**String**> |  | [optional]
**printer_brand** | Option<[**models::PrinterBrand**](PrinterBrand.md)> |  | [optional]
**printer_ip** | Option<**String**> |  | [optional]
**printer_port** | Option<**i32**> | TCP port for the receipt printer. Defaults to `9100` if absent. | [optional]
**timezone** | Option<**String**> | IANA timezone name. If absent, the branch inherits the org's timezone. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


