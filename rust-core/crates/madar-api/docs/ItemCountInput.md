# ItemCountInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**counted_qty** | Option<**f64**> | The figure counted. `null` un-counts the line: its figure, reason and counter are cleared and finalize treats it as not counted. Required (omitting it is refused), so no client un-counts by accident. | 
**note** | Option<**String**> |  | [optional]
**org_ingredient_id** | **uuid::Uuid** |  | 
**variance_reason** | Option<**String**> | Why the count differs from book stock. One of: theft | spoilage | breakage | miscount | supplier_short | transfer_error | other. Required at finalize for rows whose difference exceeds the org's threshold. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


