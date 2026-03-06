import streamlit as st
from snowflake.snowpark.context import get_active_session
import pandas as pd

st.set_page_config(page_title="Helios Grid Control Room", page_icon="⚡", layout="wide")

session = get_active_session()

@st.cache_data(ttl=300)
def load_dashboard_feed():
    return session.sql("""
        SELECT CONSUMPTION_DATE, TARIFF_TYPE, ACORN_GROUP, ACTIVE_HOUSEHOLDS,
               READING_COUNT, TOTAL_KWH, AVG_KWH_PER_READING, AVG_TEMPERATURE_C
        FROM HELIOS_ANALYTICS_DB.GRID.V_DASHBOARD_FEED
        ORDER BY CONSUMPTION_DATE
    """).to_pandas()

@st.cache_data(ttl=300)
def load_forecast_data():
    return session.sql("""
        SELECT household_id, forecast_timestamp, predicted_kwh,
               lower_bound, upper_bound, model_version
        FROM HELIOS_AI_READY_DB.GRID.CORTEX_LOAD_FORECAST
        ORDER BY forecast_timestamp
    """).to_pandas()

@st.cache_data(ttl=300)
def get_filter_options():
    df = session.sql("SELECT DISTINCT TARIFF_TYPE, ACORN_GROUP FROM HELIOS_ANALYTICS_DB.GRID.V_DASHBOARD_FEED").to_pandas()
    return df["TARIFF_TYPE"].dropna().unique().tolist(), df["ACORN_GROUP"].dropna().unique().tolist()

st.title("⚡ Live Grid Control Room")
st.caption("Project Helios | Smart Grid Energy Monitoring & Forecasting")

st.sidebar.header("🎛️ Control Panel")
tariff_options, acorn_options = get_filter_options()
selected_tariffs = st.sidebar.multiselect("Tariff Type", tariff_options, default=tariff_options)
selected_acorns = st.sidebar.multiselect("ACORN Group", acorn_options, default=acorn_options)

st.sidebar.divider()
current_role = session.sql("SELECT CURRENT_ROLE()").collect()[0][0]
st.sidebar.caption(f"Role: {current_role}")

df_raw = load_dashboard_feed()
df_forecast = load_forecast_data()

df_filtered = df_raw.copy()
if selected_tariffs:
    df_filtered = df_filtered[df_filtered["TARIFF_TYPE"].isin(selected_tariffs)]
if selected_acorns:
    df_filtered = df_filtered[df_filtered["ACORN_GROUP"].isin(selected_acorns)]

st.subheader("📊 Grid Status Overview")

if df_filtered.empty:
    st.warning("No data for selected filters.")
else:
    total_households = int(df_filtered["ACTIVE_HOUSEHOLDS"].sum())
    total_kwh = float(df_filtered["TOTAL_KWH"].sum())
    avg_temp = df_filtered["AVG_TEMPERATURE_C"].mean()
    avg_temp = float(avg_temp) if pd.notna(avg_temp) else 0.0
    total_readings = int(df_filtered["READING_COUNT"].sum())
    
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Total Households", f"{total_households:,}")
    c2.metric("Total Energy (kWh)", f"{total_kwh:,.2f}")
    c3.metric("Avg Temp (°C)", f"{avg_temp:.1f}")
    c4.metric("Total Readings", f"{total_readings:,}")

st.divider()
st.subheader("📈 Historical Energy Consumption")

if not df_filtered.empty:
    daily = df_filtered.groupby("CONSUMPTION_DATE", as_index=False).agg({"TOTAL_KWH": "sum"})
    daily["CONSUMPTION_DATE"] = pd.to_datetime(daily["CONSUMPTION_DATE"])
    daily = daily.sort_values("CONSUMPTION_DATE")
    
    if len(daily) > 0:
        col1, col2 = st.columns([3, 1])
        with col1:
            chart_data = daily.set_index("CONSUMPTION_DATE")[["TOTAL_KWH"]]
            chart_data.columns = ["Energy (kWh)"]
            st.line_chart(chart_data, height=350)
        with col2:
            st.markdown("**Summary**")
            st.write(f"Peak: {daily['TOTAL_KWH'].max():,.2f} kWh")
            st.write(f"Low: {daily['TOTAL_KWH'].min():,.2f} kWh")
            st.write(f"Avg: {daily['TOTAL_KWH'].mean():,.2f} kWh")
    
    with st.expander("📋 View Data"):
        st.dataframe(df_filtered.reset_index(drop=True), use_container_width=True)

st.divider()
st.subheader("🔮 Cortex ML Load Forecast")

if df_forecast.empty:
    st.info("Forecast data not yet available. Train the Cortex ML model to see predictions here.")
else:
    forecast_agg = df_forecast.groupby("forecast_timestamp", as_index=False).agg({
        "predicted_kwh": "sum", "lower_bound": "sum", "upper_bound": "sum"
    })
    forecast_agg = forecast_agg.sort_values("forecast_timestamp")
    forecast_agg["forecast_timestamp"] = pd.to_datetime(forecast_agg["forecast_timestamp"])
    
    fc1, fc2, fc3 = st.columns(3)
    fc1.metric("Forecast Periods", f"{len(forecast_agg)}")
    fc2.metric("Total Predicted", f"{forecast_agg['predicted_kwh'].sum():,.2f} kWh")
    fc3.metric("Model", df_forecast["model_version"].iloc[0] if len(df_forecast) > 0 else "N/A")
    
    st.markdown("**Predicted Load with Confidence Intervals**")
    chart_fc = forecast_agg.set_index("forecast_timestamp")[["lower_bound", "predicted_kwh", "upper_bound"]]
    chart_fc.columns = ["Lower", "Predicted", "Upper"]
    st.area_chart(chart_fc, height=350)
    
    with st.expander("📋 View Forecast Data"):
        st.dataframe(forecast_agg.reset_index(drop=True), use_container_width=True)

st.divider()
st.caption("Project Helios | Live Grid Control Room")