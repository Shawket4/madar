# ItemCountInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**counted_qty** | **f64** |  | 
**note** | Option<**String**> |  | [optional]
**org_ingredient_id** | **uuid::Uuid** |  | 
**variance_reason** | Option<**String**> | Why the count differs from expected. One of: theft | spoilage | breakage | miscount | supplier_short | transfer_error | other. Required at finalize for rows whose difference exceeds the org's variance threshold. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


