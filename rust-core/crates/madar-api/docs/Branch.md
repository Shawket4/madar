# Branch

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**address** | Option<**String**> |  | [optional]
**code** | Option<**String**> | Short org-unique branch prefix (A-Z0-9) embedded in every order_ref (`<CODE>-YYMMDD-…`). Exposed so an offline device can mint the same ref the server would, from first boot, without waiting for a synced order. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**geo_radius_meters** | Option<**i32**> | Radius in meters within which this branch is considered a match. Defaults to 200. | [optional]
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**latitude** | Option<**f64**> | WGS-84 latitude for geofenced branch resolution. | [optional]
**longitude** | Option<**f64**> | WGS-84 longitude for geofenced branch resolution. | [optional]
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**org_logo_url** | Option<**String**> | Convenience field — populated from the parent org's `logo_url`. | [optional]
**phone** | Option<**String**> |  | [optional]
**printer_brand** | Option<[**models::PrinterBrand**](PrinterBrand.md)> |  | [optional]
**printer_ip** | Option<**String**> |  | [optional]
**printer_port** | Option<**i32**> |  | [optional]
**timezone** | **String** | Effective IANA timezone name for this branch, resolved as `branch.timezone → org.timezone → Africa/Cairo`. Always present; clients should format all of this branch's timestamps in this zone. | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


