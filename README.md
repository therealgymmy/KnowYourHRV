# KnowYourHRV

KnowYourHRV is a simple Apple Watch app for checking your latest heart rate
variability (HRV) and using it as a lightweight stress or recovery signal.

The app reads HRV from Apple Health, compares the latest reading against your
recent baseline, and shows a friendly state:

```text
Rested
Steady
Strained
Wired
```

The goal is not to diagnose stress. It is to give you a quick sense of whether
your current HRV looks above, near, or below your usual pattern.

## Current Features

- Apple Watch-only app.
- Reads HRV from HealthKit using `heartRateVariabilitySDNN`.
- Calculates a personal baseline from recent HRV samples.
- Infers a simple stress/recovery state from latest HRV vs baseline.
- Shows a glanceable watch UI with:
  - stress signal gauge
  - latest HRV value
  - emoji state
  - comparison to usual HRV
  - freshness of the latest HRV sample
- Auto-refreshes when the app opens or becomes active.
- Includes simulator-only sample data so the UI can be tested without Apple Health data.
- Supports an Apple Watch corner complication showing the latest HRV state.

## Notes

HRV is personal and noisy. A low reading can reflect stress, poor sleep, illness,
alcohol, dehydration, overtraining, or measurement noise. KnowYourHRV compares
your HRV to your own recent baseline instead of treating one number as universal.
