# HRV: How It Works

This app uses heart rate variability (HRV) as a simple recovery and strain signal.
It should not present HRV as a medical diagnosis or a precise stress measurement.

## What HRV Means

HRV is the variation in time between heartbeats.

For example, if someone's heart rate is about 60 beats per minute, the beats are
not usually spaced exactly 1,000 milliseconds apart. One gap might be 920 ms,
the next 1,080 ms, then 970 ms. HRV summarizes that beat-to-beat variation.

In general:

- Higher HRV often suggests better recovery, flexibility, and nervous system balance.
- Lower HRV often suggests strain, fatigue, stress, poor sleep, illness, alcohol,
  dehydration, overtraining, or measurement noise.

The important part is that HRV is personal. A value that is normal for one person
may be unusually low or high for another.

## Apple Watch HRV

Apple Watch stores HRV in HealthKit as `heartRateVariabilitySDNN`.

SDNN is measured in milliseconds. Consumer HRV values often fall somewhere around
20-100 ms, but there is no single universal "good" number.

Rough population-style ranges:

```text
Very low:      < 20 ms
Lower:       20-40 ms
Common:      40-70 ms
High:        70-100 ms
Very high:   100+ ms
```

These ranges are only background context. The app should primarily compare a
person's current HRV against their own baseline.

## Inferring Stress Or Strain

The app should infer stress by comparing the latest HRV value to the user's
normal HRV baseline.

Basic model:

```text
baseline = user's typical HRV over the last 21-30 days
latest   = most recent HRV reading
change   = (latest - baseline) / baseline
```

Example:

```text
User's baseline: 60 ms
Latest HRV:      45 ms

change = (45 - 60) / 60 = -25%

Signal: Wired
```

This is more useful than interpreting the latest value alone:

```text
Person A usual HRV: 30 ms
Today:              28 ms
Signal: probably normal

Person B usual HRV: 80 ms
Today:              28 ms
Signal: major strain
```

Same HRV value, different meaning.

## Suggested V1 Bands

The app should use friendly state labels instead of clinical language.

```text
Latest vs baseline      App state
---------------------------------
+15% or more            Recovering
-10% to +15%            Steady
-10% to -25%            Strained
-25% or lower           Wired
```

Possible implementation:

```swift
if latest > baseline * 1.15 {
    state = .recovering
} else if latest >= baseline * 0.90 {
    state = .steady
} else if latest >= baseline * 0.75 {
    state = .strained
} else {
    state = .wired
}
```

## Data Rules

For a useful first version:

- Use the latest HRV sample for the current signal.
- Use the last 21-30 days to calculate the user's baseline.
- Ignore obvious outliers so one unusual reading does not distort the baseline.
- Show a "no signal" state if there is no HRV data.
- Show a "stale signal" state if the latest HRV reading is old.
- Avoid making strong claims from a single reading.

## Product Language

Use language like:

- "Below usual"
- "Near usual"
- "Above usual"
- "Recovery signal"
- "Strain signal"
- "Looks steady"

Avoid language like:

- "You are stressed"
- "Stress diagnosis"
- "Healthy/unhealthy"
- "Normal/abnormal"
- "Medical risk"

## Watch UI Direction

The watch app should be glanceable and simple:

```text
Current state: Calm / Steady / Strained / Wired / Recovering
Latest HRV:    48 ms
Compared to:   Usual 52 ms, -8%
Freshness:     18 min ago
Trend:         Small 7-day bar chart
```

The key idea is:

```text
Do not tell the user what their HRV means globally.
Tell them how today's signal compares with their usual pattern.
```
