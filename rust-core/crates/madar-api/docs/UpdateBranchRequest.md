# UpdateBranchRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**address** | Option<**String**> |  | [optional]
**geo_radius_meters** | Option<**i32**> |  | [optional]
**is_active** | Option<**bool**> |  | [optional]
**latitude** | Option<**f64**> |  | [optional]
**longitude** | Option<**f64**> |  | [optional]
**name** | Option<**String**> |  | [optional]
**old_bill_hours** | Option<**u32**> | Hours after which an open bill counts as old (1..168). | [optional]
**phone** | Option<**String**> |  | [optional]
**printer_brand** | Option<[**models::PrinterBrand**](PrinterBrand.md)> |  | [optional]
**printer_ip** | Option<**String**> |  | [optional]
**printer_port** | Option<**i32**> |  | [optional]
**require_table_for_orders** | Option<**bool**> |  | [optional]
**service_charge_rate** | Option<**f64**> |  | [optional]
**service_charge_taxable** | Option<**bool**> |  | [optional]
**standard_float** | Option<**u32**> | Standard opening float in minor units (>= 0); explicit `null` clears it. | [optional]
**tax_inclusive** | Option<**bool**> |  | [optional]
**tax_rate** | Option<**f64**> |  | [optional]
**timezone** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


