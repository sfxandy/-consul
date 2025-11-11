package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strings"

	"github.com/yourorg/svc-handler/internal/consulx"
	"github.com/yourorg/svc-handler/internal/model"
)

const (
	kvDesiredPrefix = "svc-handler/desired/"
	kvLockPrefix    = "svc-handler/locks/"
)

func (s *Server) putService(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimPrefix(r.URL.Path, "/services/")
	if name == "" {
		http.Error(w, "missing name", http.StatusBadRequest)
		return
	}
	var spec model.ServiceSpec
	if err := json.NewDecoder(r.Body).Decode(&spec); err != nil {
		http.Error(w, "bad json", http.StatusBadRequest)
		return
	}
	spec.Name = name
	if err := model.Validate(&spec); err != nil {
		write422(w, err)
		return
	}

	ctx := r.Context()
	key := kvKeyForDesired(&spec)
	if err := consulx.PutDesired(ctx, s.consul, key, &spec); err != nil {
		writeConsulErr(w, "kv.put", err)
		return
	}

	lockKey := kvKeyForLock(&spec)
	lock, err := consulx.Acquire(ctx, s.consul, lockKey, hostID(), s.lockTTL, s.lockTry)
	if err != nil {
		if errors.Is(err, consulx.ErrLockHeld) {
			http.Error(w, "conflict: operation in progress", http.StatusConflict)
			return
		}
		writeConsulErr(w, "lock.acquire", err)
		return
	}
	defer lock.Release(context.Background())

	if err := consulx.UpsertServiceDefaults(ctx, s.consul, &spec); err != nil {
		writeStepErr(w, "service-defaults", err)
		return
	}
	if err := consulx.UpsertTGWBinding(ctx, s.consul, s.tgwService, &spec); err != nil {
		writeStepErr(w, "terminating-gateway", err)
		return
	}
	if spec.Router != nil {
		if err := consulx.UpsertServiceRouter(ctx, s.consul, &spec); err != nil {
			writeStepErr(w, "service-router", err)
			return
		}
	}
	if err := consulx.Verify(ctx, s.consul, s.tgwService, &spec); err != nil {
		writeStepErr(w, "verify", err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"name":   spec.Name,
		"status": "applied",
		"observed": map[string]string{
			"service-defaults": "ok",
			"tgw":              "ok",
			"service-router":   ternary(spec.Router != nil, "ok", "skipped"),
		},
	})
}

func (s *Server) getService(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimPrefix(r.URL.Path, "/services/")
	if name == "" {
		http.Error(w, "missing name", http.StatusBadRequest)
		return
	}
	// For simplicity assume default/default. (You can extend path/query later.)
	specKey := kvDesiredPrefix + "default/default/" + name
	spec, ok, err := consulx.GetDesired(r.Context(), s.consul, specKey)
	if err != nil {
		writeConsulErr(w, "kv.get", err)
		return
	}
	if !ok {
		http.NotFound(w, r)
		return
	}
	obs, err := consulx.Observe(r.Context(), s.consul, s.tgwService, spec)
	if err != nil {
		writeConsulErr(w, "observe", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"desired":  spec,
		"observed": obs,
	})
}

func (s *Server) delService(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimPrefix(r.URL.Path, "/services/")
	if name == "" {
		http.Error(w, "missing name", http.StatusBadRequest)
		return
	}
	spec := &model.ServiceSpec{Name: name, Partition: "default", Namespace: "default"}

	ctx := r.Context()
	lockKey := kvKeyForLock(spec)
	lock, err := consulx.Acquire(ctx, s.consul, lockKey, hostID(), s.lockTTL, s.lockTry)
	if err != nil {
		if errors.Is(err, consulx.ErrLockHeld) {
			http.Error(w, "conflict: operation in progress", http.StatusConflict)
			return
		}
		writeConsulErr(w, "lock.acquire", err)
		return
	}
	defer lock.Release(context.Background())

	_ = consulx.DeleteServiceRouter(ctx, s.consul, spec.Name)
	_ = consulx.DeleteTGWBinding(ctx, s.consul, s.tgwService, spec.Name)
	_ = consulx.DeleteServiceDefaults(ctx, s.consul, spec.Name)

	_ = consulx.DelDesired(ctx, s.consul, kvKeyForDesired(spec))

	writeJSON(w, http.StatusOK, map[string]string{"name": spec.Name, "status": "deleted"})
}

func kvKeyForDesired(s *model.ServiceSpec) string {
	return kvDesiredPrefix + fmt.Sprintf("%s/%s/%s", nz(s.Partition, "default"), nz(s.Namespace, "default"), s.Name)
}
func kvKeyForLock(s *model.ServiceSpec) string {
	return kvLockPrefix + fmt.Sprintf("%s/%s/%s", nz(s.Partition, "default"), nz(s.Namespace, "default"), s.Name)
}

func nz(s, def string) string { if s == "" { return def }; return s }
func ternary[T any](cond bool, a, b T) T { if cond { return a } ; return b }
func hostID() string { h, _ := os.Hostname(); return h }

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}
func write422(w http.ResponseWriter, err error) {
	writeJSON(w, http.StatusUnprocessableEntity, map[string]any{"error": "validation", "details": err.Error()})
}
func writeConsulErr(w http.ResponseWriter, step string, err error) {
	writeJSON(w, http.StatusBadGateway, map[string]any{"error": "consul", "step": step, "details": err.Error()})
}
func writeStepErr(w http.ResponseWriter, step string, err error) {
	writeJSON(w, http.StatusBadGateway, map[string]any{"error": "apply", "step": step, "details": err.Error()})
}
