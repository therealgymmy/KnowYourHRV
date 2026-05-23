# App Architecture

KnowYourHRV is a watch-only app with two user-facing surfaces:

1. The full Apple Watch app.
2. An Apple Watch corner complication.

The full Watch app owns the HRV calculation. The complication is a lightweight
display surface that reads the latest saved snapshot.

## Architecture Diagram

```text
Apple Health / HealthKit
        |
        | HRV samples
        | heartRateVariabilitySDNN
        v
+----------------------+
|      HRVStore        |
|  Watch app runtime   |
+----------------------+
        |
        | 1. request HealthKit access
        | 2. query last 30 days HRV
        | 3. sort latest sample
        | 4. calculate baseline
        | 5. infer stress state
        v
+----------------------+
|    HRVDashboard      |
| latest HRV           |
| baseline             |
| % from baseline      |
| stress state         |
+----------------------+
        |
        +---------------------------+
        |                           |
        v                           v
+----------------------+   +----------------------+
|    ContentView       |   |   HRVSnapshotStore   |
| Watch app UI         |   | App Group persistence|
+----------------------+   +----------------------+
        |                           |
        | shows                     | saves compact
        | gauge + latest value      | complication snapshot
        v                           v
+----------------------+   +----------------------+
| Watch App Screen     |   | App Group UserDefaults|
| Stress Signal gauge  |   | latestHRVSnapshot     |
+----------------------+   +----------------------+
                                    |
                                    | complication reads
                                    v
                           +----------------------+
                           | KnowHRV Complication |
                           | WidgetKit extension  |
                           +----------------------+
                                    |
                                    v
                           +----------------------+
                           | Watch Face Corner    |
                           | emoji + curved label |
                           +----------------------+
```

## HealthKit Layer

HealthKit is the raw HRV data source.

The app reads:

```swift
HKQuantityTypeIdentifier.heartRateVariabilitySDNN
```

Each HealthKit HRV sample gives us:

```text
value: HRV in milliseconds
date: sample endDate
type: heartRateVariabilitySDNN
```

HealthKit does not give us:

```text
baseline HRV
stress state
Rested / Steady / Strain / Wired
gauge value
```

Those are app-level calculations.

## HRVStore

`HRVStore` is the main runtime model for the Watch app.

It is responsible for:

```text
requesting HealthKit permission
querying the last 30 days of HRV samples
falling back to fake simulator data when needed
building the HRV dashboard
publishing state to the SwiftUI app screen
saving a snapshot for the complication
```

Current store states:

```text
idle
loading
unavailable
noData
loaded(HRVDashboard)
failed
```

## Dashboard Calculation

The app converts HRV readings into an `HRVDashboard`.

The dashboard includes:

```text
latest HRV
baseline HRV
percent from baseline
stress state
```

Basic model:

```text
baseline = user's typical HRV over the last 30 days
latest   = most recent HRV reading
change   = (latest - baseline) / baseline
```

Stress state mapping:

```text
Latest vs baseline      App state
---------------------------------
+15% or more            Rested
-10% to +15%            Steady
-10% to -25%            Strained
-25% or lower           Wired
```

The complication shortens `Strained` to `Strain` to fit better in a corner slot.

## Watch App UI

`ContentView` displays the full dashboard.

The main screen shows:

```text
KnowHRV
Stress Signal gauge
Latest HRV value
Emoji + state
Compared to usual
Freshness of latest HRV sample
```

The app auto-refreshes:

```text
on first launch
when the app becomes active
only if the last app refresh was at least 60 seconds ago
```

The freshness text in the footer refers to the latest HRV sample timestamp, not
the last time the app queried HealthKit.

## Simulator Fake Data

`HRVSampleData` exists to make the Watch Simulator useful.

Behavior:

```text
if running in simulator and HealthKit returns no HRV:
    generate 30 days of fake HRV readings
else:
    use real HealthKit data
```

The fake data is deterministic and in-memory only. It is not saved to HealthKit.

This lets the app test the same dashboard and stress-state logic without needing
real HealthKit data in the simulator.

## Complication Data Flow

The complication does not query HealthKit directly right now.

Instead:

```text
Watch app computes HRVDashboard
        |
        v
Watch app saves HRVSnapshot
        |
        v
Complication reads HRVSnapshot
        |
        v
Watch face renders it
```

The snapshot is stored in an App Group using `UserDefaults`.

App Group:

```text
group.realdecaf.KnowYourHRV
```

Snapshot key:

```text
latestHRVSnapshot
```

The snapshot contains:

```text
state title
state emoji
latest HRV milliseconds
sample date
updated date
```

After saving a snapshot, the Watch app asks WidgetKit to reload the complication
timeline.

## Corner Complication

The complication is a WidgetKit extension and currently supports only:

```swift
.accessoryCorner
```

Current visual design:

```text
Steady - 48ms
     😌
```

In implementation terms:

```swift
Text("😌")
    .widgetCurvesContent()
    .widgetLabel("Steady - 48ms")
```

The emoji is the main complication content. The state and HRV value are provided
as the widget label.

watchOS decides whether that label is rendered as curved text based on the watch
face and complication slot. The app can provide the label, but it cannot force
every face or slot to render it curved.

## Mental Model

```text
HealthKit = raw data source
HRVStore = brain
ContentView = full app display
HRVSnapshotStore = bridge
WidgetKit complication = tiny watch-face display
```
