package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/hashicorp/consul/api"
	"github.com/yourorg/svc-handler/internal/api"
)

func main() {
	// Basic config from env
	addr := getenv("HTTP_ADDR", ":8080")
	consulAddr := getenv("CONSUL_HTTP_ADDR", "http://127.0.0.1:8500")
	consulToken := os.Getenv("CONSUL_HTTP_TOKEN")
	tgwService := mustGetenv("TGW_SERVICE_NAME") // e.g., "tgw-west-1"
	lockTTL := getenv("LOCK_TTL", "60s")

	cfg := api.DefaultConfig()
	cfg.Address = consulAddr
	if consulToken != "" {
		cfg.Token = consulToken
	}
	cli, err := api.NewClient(cfg)
	if err != nil {
		log.Fatalf("consul client: %v", err)
	}

	ttl, err := time.ParseDuration(lockTTL)
	if err != nil {
		log.Fatalf("LOCK_TTL parse: %v", err)
	}

	s := api2.NewServer(api2.ServerConfig{
		Consul:      cli,
		TGWService:  tgwService,
		LockTTL:     ttl,
		LockRetries: 3,
	})

	srv := &http.Server{
		Addr:         addr,
		Handler:      s.Mux(),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 90 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	go func() {
		log.Printf("listening on %s", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("http server: %v", err)
		}
	}()

	// Simple block forever (you can add signal handling if you want)
	select {}
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
func mustGetenv(k string) string {
	v := os.Getenv(k)
	if v == "" {
		log.Fatalf("missing required env %s", k)
	}
	return v
}

// import alias convenience (avoid name clash with stdlib net/http api)
var api2 = struct {
	NewServer func(api.ServerConfig) *api.Server
}{
	NewServer: api.NewServer,
}
