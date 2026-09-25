# StaffRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**attendance_record_id** | Option<**uuid::Uuid**> | The record a `correction` proposes to fix. `None` for every other kind. | [optional]
**can_decide** | Option<**bool**> | The caller may approve or reject it now: it is pending, not their own, at one of their branches, and — a manager's request — they outrank the requester (RQ-5). The same checks the decision makes. | [optional]
**cancel_note** | Option<**String**> |  | [optional]
**cancelled_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**cancelled_by** | Option<**uuid::Uuid**> | Who cancelled it (the person themselves or a manager), when and why. | [optional]
**cancelled_by_name** | Option<**String**> | Who cancelled it, by name, the same way. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**decided_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**decided_by** | Option<**uuid::Uuid**> | Who approved or rejected it, when and why. A later cancellation keeps these (the approval stays on record) and fills `cancelled_*`. | [optional]
**decided_by_name** | Option<**String**> | Who decided it, by name — their employee's name when linked, else their account's — so a phone that can't look up the owner's account still names them (RQ-F6). | [optional]
**decision_note** | Option<**String**> |  | [optional]
**employee_id** | **uuid::Uuid** |  | 
**employee_name** | Option<**String**> |  | [optional]
**end_date** | Option<**chrono::NaiveDate**> | Set for `leave` and `mission`: the span's last day. For an `excuse` that runs past midnight, the next day (its end is then on that day). | [optional]
**from_time** | Option<**String**> | Start of the excused window. `None` = open to the shift's start. For a `correction`: the proposed check-in, branch-local. | [optional]
**id** | **uuid::Uuid** |  | 
**is_half_day** | **bool** |  | 
**is_own** | Option<**bool**> | The request is the CALLER's own (worked out for whoever asks). | [optional]
**is_paid** | Option<**bool**> | Whether the excused time is paid. `None` until decided. | [optional]
**kind** | **String** | `leave` | `late_arrival` | `early_departure` | `excuse` | `mission` | `correction`. | 
**leave_half** | Option<**String**> | A half-day leave: `first` or `second` half of the day off (RQ-8). | [optional]
**leave_type_id** | Option<**uuid::Uuid**> | Deprecated (RQ-2): older rows only; never set on new requests. | [optional]
**leave_type_name** | Option<**String**> |  | [optional]
**location** | Option<**String**> |  | [optional]
**month_closed** | Option<**bool**> | A day of it is in an approved or paid month: approving or cancelling approved time is refused (PERIOD_CLOSED); rejecting still works. | [optional]
**on_date** | **chrono::NaiveDate** |  | 
**org_id** | **uuid::Uuid** |  | 
**paid_default** | Option<**bool**> | For a pending excuse or early departure: the business's (or branch's) rule, which the approve dialog starts from (RQ-7). | [optional]
**reason** | Option<**String**> |  | [optional]
**record_check_in_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | For a correction: the record's current punches, so an approver sees what the proposal changes. | [optional]
**record_check_out_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**status** | **String** |  | 
**title** | Option<**String**> |  | [optional]
**to_owner** | Option<**bool**> | A manager's own request waiting for someone above them (RQ-5): the owner decides it. Worked out by the server from capabilities. | [optional]
**to_time** | Option<**String**> | End of the excused window. `None` = open to the shift's end. For a `correction`: the proposed check-out, branch-local (earlier on the clock than the check-in = the next morning, a night shift). | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**work_shift_id** | Option<**uuid::Uuid**> | The shift a late arrival, early departure or excuse is for (split days). | [optional]
**worked_dates** | Option<**Vec<chrono::NaiveDate>**> | For a leave or mission: the days it covers that the person already clocked in on. Approving turns those worked days into leave (the punches are kept), so the approver is warned first (minor default M16). Empty for every other kind. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


