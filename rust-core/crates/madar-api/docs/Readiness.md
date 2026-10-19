# Readiness

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**checks** | [**Vec<models::ReadinessCheck>**](ReadinessCheck.md) | Blocking checks first, then advice. Empty for an org without the POS. | 
**first_order_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**live** | **bool** | The shop has taken an order. | 
**org_id** | **uuid::Uuid** |  | 
**ready** | **bool** | Every blocking check passes: a cashier can ring up and take payment. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


