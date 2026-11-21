use std::sync::OnceLock;
use std::time::Instant;

use axum::{
    extract::{MatchedPath, Request},
    middleware::Next,
    response::Response,
};
use metrics_exporter_prometheus::{Matcher, PrometheusBuilder, PrometheusHandle};

static HANDLE: OnceLock<PrometheusHandle> = OnceLock::new();

pub fn install() {
    const EXPONENTIAL_SECONDS: &[f64] = &[
        0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0,
    ];

    let handle = PrometheusBuilder::new()
        .set_buckets_for_metric(
            Matcher::Full("http_request_duration_seconds".to_string()),
            EXPONENTIAL_SECONDS,
        )
        .expect("valid histogram bucket configuration")
        .install_recorder()
        .expect("failed to install Prometheus metrics recorder");

    let upkeep_handle = handle.clone();
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(std::time::Duration::from_secs(5));
        loop {
            ticker.tick().await;
            upkeep_handle.run_upkeep();
        }
    });

    metrics::gauge!("nexora_up").set(1.0);
    metrics::gauge!("nexora_build_info", "version" => env!("CARGO_PKG_VERSION")).set(1.0);

    let _ = HANDLE.set(handle);
}

pub async fn metrics_handler() -> String {
    HANDLE
        .get()
        .map(|handle| handle.render())
        .unwrap_or_default()
}

pub async fn track_metrics(req: Request, next: Next) -> Response {
    let method = req.method().clone();
    let route = req
        .extensions()
        .get::<MatchedPath>()
        .map(|matched| matched.as_str().to_owned())
        .unwrap_or_else(|| "unmatched".to_owned());

    let start = Instant::now();
    let response = next.run(req).await;
    let duration = start.elapsed().as_secs_f64();
    let status = response.status().as_u16().to_string();

    metrics::counter!(
        "http_requests_total",
        "method" => method.to_string(),
        "route" => route.clone(),
        "status" => status.clone(),
    )
    .increment(1);

    metrics::histogram!(
        "http_request_duration_seconds",
        "method" => method.to_string(),
        "route" => route,
        "status" => status,
    )
    .record(duration);

    response
}