// Command demo-service is a minimal HTTP microservice. It's the single
// container image reused by all 10 releases of charts/microservice — only
// the SERVICE_NAME env var (set per Helm release in charts/values/) and,
// for two of the ten, the Istio sidecar and traffic policy differ between
// "instances" of it.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	// Labeled by path/method/status so one counter backs a per-route
	// request-rate panel in Grafana instead of one metric per handler.
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total HTTP requests processed, labeled by path, method and status code.",
		},
		[]string{"path", "method", "status"},
	)

	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request latency in seconds.",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"path", "method"},
	)
)

// ready flips true once startup work (simulated below) finishes. Kept
// separate from liveness deliberately: a pod can be alive (don't restart
// it) but not yet ready (don't send it traffic) — that distinction is the
// entire reason Kubernetes has two different probes.
var ready atomic.Bool

func main() {
	serviceName := getenv("SERVICE_NAME", "demo-service")
	port := getenv("PORT", "8080")

	// Simulate a small amount of startup work (cache warmup, a dependency
	// check, ...) so /readyz demonstrates something instead of always
	// just returning 200 from the first instant the process starts.
	go func() {
		time.Sleep(2 * time.Second)
		ready.Store(true)
		log.Printf("%s: ready", serviceName)
	}()

	mux := http.NewServeMux()
	mux.Handle("/", instrument("/", handleRoot(serviceName)))
	mux.Handle("/healthz", instrument("/healthz", handleHealthz()))
	mux.Handle("/readyz", instrument("/readyz", handleReadyz()))
	// Left uninstrumented on purpose — wrapping the metrics endpoint in
	// the same request counter it exposes is a pointless feedback loop.
	mux.Handle("/metrics", promhttp.Handler())

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	// Graceful shutdown: stop accepting new connections and give in-flight
	// requests a few seconds to finish on SIGTERM instead of dropping them
	// mid-response — matters during a rollout, when pods are terminated
	// routinely rather than exceptionally.
	go func() {
		stop := make(chan os.Signal, 1)
		signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
		<-stop
		log.Printf("%s: shutting down", serviceName)

		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			log.Printf("%s: graceful shutdown failed: %v", serviceName, err)
		}
	}()

	log.Printf("%s: listening on :%s", serviceName, port)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("%s: server error: %v", serviceName, err)
	}
}

func handleRoot(serviceName string) http.HandlerFunc {
	type response struct {
		Service string `json:"service"`
		Message string `json:"message"`
	}
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(response{
			Service: serviceName,
			Message: "hello from " + serviceName,
		})
	}
}

func handleHealthz() http.HandlerFunc {
	// Liveness: "is the process itself stuck" — deliberately does no
	// dependency checks, so a slow downstream never causes Kubernetes to
	// restart an otherwise-healthy pod.
	return func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	}
}

func handleReadyz() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !ready.Load() {
			http.Error(w, "starting up", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	}
}

// instrument wraps a handler with the request-count and latency metrics
// declared above.
func instrument(path string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

		next.ServeHTTP(rec, r)

		httpRequestsTotal.WithLabelValues(path, r.Method, strconv.Itoa(rec.status)).Inc()
		httpRequestDuration.WithLabelValues(path, r.Method).Observe(time.Since(start).Seconds())
	})
}

// statusRecorder captures the status code a handler wrote, since
// http.ResponseWriter doesn't expose it after the fact.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
