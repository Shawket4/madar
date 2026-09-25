# SalaryAdvance

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_piastres** | **i64** |  | 
**cap_piastres** | Option<**i64**> | The owner's cap on what this person may owe in advances, in piastres (AV-5) — the server's figure, so no client recomputes it. Null for a caller who may not read this person's salary: the cap is half the salary, so it would give it away (owner decision D7). The person always sees their own. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**decided_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**decided_by** | Option<**uuid::Uuid**> |  | [optional]
**decision_note** | Option<**String**> |  | [optional]
**employee_id** | **uuid::Uuid** |  | 
**employee_name** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**installments** | **i32** |  | 
**monthly_installment_piastres** | **i64** |  | 
**org_id** | **uuid::Uuid** |  | 
**outstanding_piastres** | **i64** | What the person owes across their live advances (pending ones count). | 
**reason** | Option<**String**> |  | [optional]
**remaining_piastres** | **i64** | Derived from the collection ledger (AV-6). | 
**status** | **String** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**within_cap** | **bool** | What is owed (pending ones counted) is within the cap: what a manager sees instead of the cap (D7). False = over it: only the owner can approve more. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


