# PackagingRuleOut

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**lines** | [**Vec<models::PackagingRuleLineOut>**](PackagingRuleLineOut.md) |  | 
**match_category_id** | Option<**uuid::Uuid**> | Menu category (`categories.id`) the rule matches, or `null` = any. | [optional]
**match_item_id** | Option<**uuid::Uuid**> | One menu item the rule matches, or `null` = any. | [optional]
**match_size_label** | Option<**String**> | Exact size label the rule matches (`Cup`, `Can`), or `null` = any. | [optional]
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**sort** | **i32** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


