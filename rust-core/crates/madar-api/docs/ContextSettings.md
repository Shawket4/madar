# ContextSettings

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**absence_deduction_days** | **f64** |  | 
**advance_cap_percent** | **f64** |  | 
**holiday_multiplier** | **f64** |  | 
**late_deduction_tiers** | Option<**serde_json::Value**> |  | 
**overtime_day_multiplier** | **f64** |  | 
**overtime_mode** | **String** |  | 
**overtime_night_multiplier** | **f64** |  | 
**period_start_day** | **i32** |  | 
**rules_saved** | **bool** | The business saved its rules; nobody clocks in before (RU-1, DSH-6). | 
**rules_saved_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the rules were first saved; null until then. The sweep never marks absent (or charges) a shift that started before it (B-SETUP-5), so neither does the app (B-ONB-1). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


