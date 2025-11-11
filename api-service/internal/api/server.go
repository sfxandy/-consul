package api

import (
	"net/http"
	"time"

	"github.com/hashicorp/consul/api"
)

type ServerConfig struct {
	Consul      *api.Client
	TGWService  string
	LockTTL     time.Duration
	LockRetries int
}

type Server struct {
	mux        *http.ServeMux
	consul     *api.Client
	tgwService string
	lockTTL    time.Duration
	lockTry    int
}

func NewServer(cfg ServerConfig) *Server {
	s := &Server{
		mux:        http.NewServeMux(),
		consul:     cfg.Consul,
		tgwService: cfg.TGWService,
		lockTTL:    cfg.LockTTL,
		lockTry:    cfg.LockRetries,
	}
	// Routes (Go 1.22+ patterns)
	s.mux.HandleFunc("GET /healthz", s.healthz)
	s.mux.HandleFunc("GET /readyz", s.readyz)
	s.mux.HandleFunc("PUT /services/", s.putService)    // /services/{name}
	s.mux.HandleFunc("GET /services/", s.getService)    // /services/{name}
	s.mux.HandleFunc("DELETE /services/", s.delService) // /services/{name}
	return s
}

func (s *Server) Mux() *http.ServeMux { return s.mux }

func (s *Server) healthz(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}
func (s *Server) readyz(w http.ResponseWriter, r *http.Request) {
	if _, err := s.consul.Status().Leader(); err != nil {
		http.Error(w, "consul unavailable", http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ready"))
}
