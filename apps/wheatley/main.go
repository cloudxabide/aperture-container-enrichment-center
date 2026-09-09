// wheatley — a deliberately tiny HTTP server for the distroless chamber.
//
// One binary, one process, no forking, no shelling out. That is the whole
// point: the learned NeuVector baseline for this workload is "listen on :8080,
// serve HTTP, make no outbound connections", which makes every step of the
// Chamber 05 walkthrough (attach busybox, wget EICAR) obviously anomalous.
//
// Built multi-stage onto gcr.io/distroless/static-debian12:nonroot — see the
// Dockerfile. Keep this file dependency-free (standard library only) so the
// build stays trivial and the final image stays empty of anything an attacker
// could use.
package main

import (
	"log"
	"net/http"
	"os"
	"time"
)

const banner = "I am NOT a moron... but I might be a tiny bit thick.\n"

func main() {
	addr := ":8080"
	if p := os.Getenv("WHEATLEY_ADDR"); p != "" {
		addr = p
	}

	mux := http.NewServeMux()

	// GET /healthz — liveness/readiness probe target. Cheap, no logging.
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("OK\n"))
	})

	// GET / — the Portal-flavoured payload. Anything not /healthz lands here.
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s %s", r.RemoteAddr, r.Method, r.URL.Path)
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(banner))
	})

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("wheatley listening on %s", addr)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("wheatley: %v", err)
	}
}
