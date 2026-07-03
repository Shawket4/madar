# OrgIngredient

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category** | **String** |  | 
**cost_per_unit** | Option<**f64**> | Piastres per unit. `null` ⟺ never entered (unknown, NOT free) — recipes using this ingredient are cost-missing everywhere. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**density_g_per_ml** | Option<**f64**> | Grams per millilitre, bridging weight↔volume in recipes; `null` = none. | [optional]
**description** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**pack_size** | Option<**f64**> | How many BASE STOCK units one `pack_unit` yields; `null` = none. | [optional]
**pack_unit** | Option<**String**> | Named purchase pack (e.g. \"case\", \"sack\"); `null` = none. | [optional]
**supplier_id** | Option<**uuid::Uuid**> | Default supplier for reordering this ingredient; `null` = none set. | [optional]
**supplier_name** | Option<**String**> |  | [optional]
**unit** | **String** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**yield_pct** | Option<**f64**> | Usable % after trim/cook loss (e.g. 70 = 70%); `null` = 100%. Recipe quantities are grossed up by this at save time. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


