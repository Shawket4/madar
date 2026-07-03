# KitchenStation

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**is_default** | **bool** |  | 
**name** | **String** |  | 
**name_translations** | Option<**serde_json::Value**> |  | 
**org_id** | **uuid::Uuid** |  | 
**printer_brand** | Option<[**models::PrinterBrand**](PrinterBrand.md)> |  | [optional]
**printer_ip** | Option<**String**> |  | [optional]
**printer_port** | Option<**i32**> |  | [optional]
**sort_order** | **i32** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


