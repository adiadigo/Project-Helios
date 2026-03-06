# Analysis Mindset: Live Grid Control Room Dashboard

## The Analyst's Perspective

This document explains the reasoning behind every data point, metric, and visualization in the Helios Grid Control Room dashboard. It answers the question: **why are we showing this, and what decision does it support?**

---

## User Story

Sarah is a Grid Operations Analyst at a London energy utility. Every morning, she opens the Live Grid Control Room to assess the state of the distribution network. She needs to answer three questions within 60 seconds:

1. **"Is the grid healthy?"** - Are households reporting? Is consumption within normal range?
2. **"What happened yesterday?"** - Did consumption spike or drop? Was it weather-related?
3. **"What should I expect tomorrow?"** - Will demand increase? Should I alert the operations team?

The dashboard is designed to answer these three questions in order, from top to bottom.

---

## Section 1: Sidebar Filters

### What is Shown

Two multi-select filters:
- **Tariff Type** (Standard, Time-of-Use)
- **ACORN Group** (Affluent, Comfortable, Adversity, ACORN-U)

### Why These Filters

Sarah's primary analytical workflow requires slicing data by these two dimensions:

**Tariff Type** determines pricing behavior. Standard tariff customers have flat-rate pricing with no incentive to shift load. Time-of-Use customers pay variable rates, creating predictable demand patterns (lower usage during peak price periods). Comparing these groups reveals whether pricing signals actually change consumption behavior.

**ACORN Group** is a UK demographic classification system. Different socioeconomic groups have different consumption profiles. Affluent households tend to have larger properties with higher baseline consumption. Adversity households may have energy poverty concerns where low consumption warrants investigation rather than celebration.

Both filters update all dashboard queries simultaneously, enabling rapid drill-down without navigating to separate pages.

---

## Section 2: Grid Status Overview (KPI Cards)

### What is Shown

Four metrics:
- Total Households
- Total Energy (kWh)
- Avg Temperature (C)
- Total Readings

### Why These Metrics

**Total Households** answers "are meters reporting?" This is the first health check. A sudden drop means meters have gone offline, indicating communication failures, power outages, or data pipeline issues. Sarah compares this number to the expected baseline (30 households in our dataset). If it drops below that, something is wrong upstream.

**Total Energy (kWh)** is the primary operational metric. This is the net energy distributed through the grid segment. It drives capacity planning, billing, and regulatory reporting. Sarah looks at this as an absolute number to gauge load volume.

**Avg Temperature (C)** provides immediate context for consumption levels. Energy consumption in the UK is heavily weather-driven: heating demand rises below 15C, and the relationship is roughly linear below 10C. By placing temperature alongside consumption, Sarah can instantly judge whether today's load is weather-driven or anomalous.

**Total Readings** is a data quality indicator. If total readings drops while household count stays the same, it means meters are reporting intermittently. If readings increase while households stay flat, it indicates higher reporting frequency. This metric catches silent data quality issues that would be invisible in consumption totals alone.

### Design Decision: Why Not Show Revenue or Cost?

Revenue depends on tariff rates, contract terms, and billing cycles that are outside the scope of meter telemetry data. Mixing operational metrics with financial metrics creates confusion about data freshness (billing data lags by days; meter data is near real-time). Cost management has its own dedicated page.

---

## Section 3: Historical Energy Consumption (Line Chart)

### What is Shown

A time-series line chart of daily total kWh consumption, with a summary panel showing peak, low, and average values.

### Why a Line Chart

Time-series consumption data has three key properties that make line charts the correct visualization:

1. **Temporal ordering matters.** Energy consumption follows daily and seasonal cycles. Bar charts obscure the continuity between data points. A line chart reveals trends, cycles, and discontinuities.

2. **Adjacent points are correlated.** Today's consumption is strongly related to yesterday's consumption. The line connecting points communicates this relationship visually.

3. **Anomalies are visible as pattern breaks.** A sudden spike or drop in the line immediately draws the eye, which is the primary analytical goal: "did something unusual happen?"

### Why Daily Aggregation

The raw data contains half-hourly readings. Aggregating to daily level serves the dashboard's purpose as a strategic overview tool. Intra-day patterns (morning peak, evening peak) require a different visualization and a different analytical context. The daily view answers "what's the trend this week?" not "what happened at 6 PM."

### Why the Summary Panel

The peak, low, and average statistics provide anchoring numbers that persist even as Sarah adjusts filters. They answer:

- **Peak**: "What was the maximum load I need to plan capacity for?"
- **Low**: "What's the baseline demand when the grid is quiet?"
- **Average**: "What's the typical daily throughput?"

The spread between peak and low indicates demand volatility. A narrow spread suggests predictable, stable demand. A wide spread suggests the grid segment experiences significant load swings.

### The Expander: Detailed Data

The expandable table allows Sarah to inspect individual records when the chart reveals something unusual. Rather than building a separate detail page, the expander keeps the analytical flow intact: see the chart, notice an anomaly, expand to investigate.

---

## Section 4: Cortex ML Load Forecast (Area Chart)

### What is Shown

When forecast data is available:
- Three KPI cards (forecast horizon, total predicted kWh, model version)
- An area chart showing predicted consumption with upper and lower confidence bounds

When forecast data is not available:
- An informational message explaining the expected schema

### Why Forecasting Matters

Historical data tells Sarah what happened. Forecasting tells her what to prepare for. In grid operations, this distinction has operational consequences:

- If tomorrow's predicted load exceeds current capacity, she escalates to the capacity planning team
- If the confidence interval is wide, she knows the prediction is uncertain and plans for contingency
- If the model version changes, she knows the prediction methodology has been updated

### Why Area Chart for Confidence Intervals

The area chart renders three overlapping layers: lower bound, predicted value, and upper bound. The visual "thickness" of the shaded area communicates uncertainty at a glance:

- **Thin band**: High confidence. The model is certain about its prediction.
- **Wide band**: Low confidence. External factors (unusual weather, holidays, events) make prediction difficult.

This is more intuitive than showing three separate lines, which would require the viewer to mentally compute the gap between them.

### Why Show Model Version

Model version is a governance metric. When Sarah sees a forecast that seems off, her first question is "did the model change?" Displaying the version avoids unnecessary investigation when predictions shift due to model retraining rather than actual demand changes.

### The Empty State

When no forecast data exists, the dashboard does not show a blank space or error. Instead, it explains what will appear and why, along with the expected data schema. This serves dual purposes: it sets expectations for the user, and it documents the integration contract for the engineering team.

---

## Filter Interaction Design

All four sections respond to the sidebar filters. This is a deliberate design choice:

**Consistent filtering** means Sarah can select "Time-of-Use + Affluent" and see KPIs, trends, and forecasts all scoped to that segment. This enables segment-level operational decisions.

**Default: all selected** means the initial view shows the full grid picture. Sarah starts broad and narrows as questions arise.

**Multi-select** (not single-select) allows comparison between segments. Selecting both "Affluent" and "Adversity" while deselecting others reveals whether these groups have divergent consumption patterns.

---

## Data Source Decisions

### Why V_DASHBOARD_FEED (Not Raw Fact Table)

The dashboard queries `V_DASHBOARD_FEED`, a pre-aggregated Gold layer view, rather than querying `FACT_ENERGY_CONSUMPTION` directly. Reasons:

1. **Performance**: The view pre-computes daily aggregations, joins to dimension tables, and calculates averages. The dashboard does not need to repeat these calculations on every page load.

2. **Consistency**: All consumers of this view get the same aggregation logic. If the aggregation formula changes, it changes once in the view definition.

3. **Governance**: The view inherits masking policies from the underlying tables. Depending on the user's role, household_id and acorn_group appear masked, partially masked, or unmasked.

### Why CORTEX_LOAD_FORECAST (Not Live Inference)

The dashboard reads pre-computed forecasts from a table rather than invoking Cortex ML at query time. This is intentional:

1. **Cost control**: ML inference consumes credits. Running a forecast on every dashboard refresh would be expensive and wasteful.

2. **Consistency**: All viewers see the same forecast. If forecasts were computed per-session, different users could see different predictions at the same moment.

3. **Auditability**: Stored forecasts have timestamps and model versions. If a capacity decision is questioned later, the exact prediction that informed it can be retrieved.

---

## What This Dashboard Does Not Do (And Why)

| Deliberately Excluded | Rationale |
|----------------------|-----------|
| Real-time streaming updates | Dashboard is for shift-start overview, not second-by-second monitoring |
| Individual household drill-down | PII governance restricts household-level visibility by role |
| Cost/billing metrics | Billing data has different latency and ownership than operational data |
| Alert management | Alerts are handled by Snowflake's native alert system, not a dashboard |
| Data quality checks | Data quality is validated in the pipeline, not in the presentation layer |

---

## Reading the Dashboard: A Walkthrough

**Step 1**: Sarah opens the dashboard. All filters are selected. She scans the four KPIs.
- "30 households reporting. Good, all meters are up."
- "Total kWh looks reasonable for this time of year."
- "Temperature is 9.4C, cold enough for heating load."

**Step 2**: She looks at the historical trend line.
- "Consumption has been stable this week. No spikes."
- "The average is 32 kWh per day across the segment."

**Step 3**: She filters to "Time-of-Use" only.
- "ToU customers are consuming less during peak hours as expected."
- "Their average is lower than Standard customers."

**Step 4**: She checks the forecast section.
- "Model predicts 35 kWh for tomorrow. Within normal range."
- "Confidence interval is narrow. High certainty."

**Step 5**: She closes the dashboard and starts her operational shift. Total time: under 60 seconds.

---

*Document Version: 1.0*
*Last Updated: 2026-02-27*
*Project Codename: HELIOS*
