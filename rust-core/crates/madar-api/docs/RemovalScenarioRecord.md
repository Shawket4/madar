# RemovalScenarioRecord

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**absorbed_by** | [**Vec<models::AbsorbedBy>**](AbsorbedBy.md) |  | 
**baseline_cm** | **f64** |  | 
**complementary_losses** | [**Vec<models::ComplementaryLoss>**](ComplementaryLoss.md) |  | 
**explanation** | **String** |  | 
**item_name** | **String** |  | 
**key** | [**models::ItemKey**](ItemKey.md) |  | 
**net_cm_change** | **f64** |  | 
**net_cm_change_hi** | **f64** |  | 
**net_cm_change_lo** | **f64** |  | 
**recommendation** | [**models::RemovalRecommendation**](RemovalRecommendation.md) |  | 
**branch_id** | **uuid::Uuid** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**decision** | Option<[**models::DecisionRecord**](DecisionRecord.md)> |  | [optional]
**id** | **uuid::Uuid** |  | 
**run_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


