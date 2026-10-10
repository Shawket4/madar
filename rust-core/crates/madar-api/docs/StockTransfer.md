# StockTransfer

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cancelled** | Option<[**models::TransferStamp**](TransferStamp.md)> |  | [optional]
**created** | [**models::TransferStamp**](TransferStamp.md) |  | 
**destination_branch_id** | **uuid::Uuid** |  | 
**destination_branch_name** | **String** |  | 
**destination_kind** | [**models::BranchKind**](BranchKind.md) |  | 
**dispatched** | Option<[**models::TransferStamp**](TransferStamp.md)> |  | [optional]
**id** | **uuid::Uuid** |  | 
**lines** | [**Vec<models::StockTransferLine>**](StockTransferLine.md) |  | 
**note** | Option<**String**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**received** | Option<[**models::TransferStamp**](TransferStamp.md)> |  | [optional]
**reference** | **String** | `TR-1043`, per org. | 
**requested** | Option<[**models::TransferStamp**](TransferStamp.md)> |  | [optional]
**source_branch_id** | **uuid::Uuid** |  | 
**source_branch_name** | **String** |  | 
**source_kind** | [**models::BranchKind**](BranchKind.md) |  | 
**status** | [**models::TransferStatus**](TransferStatus.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


