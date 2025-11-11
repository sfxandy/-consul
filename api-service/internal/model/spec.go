package model

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
)

type ServiceSpec struct {
	Name      string            `json:"name"`
	Partition string            `json:"partition"`
	Namespace string            `json:"namespace"`
	Routing   Routing           `json:"routing"`
	Connect   *Connect          `json:"connect,omitempty"`
	Router    *Router           `json:"router,omitempty"`
	Metadata  map[string]any    `json:"metadata,omitempty"`
	Labels    map[string]string `json:"labels,omitempty"`
}

type Routing struct {
	Host string  `json:"host"`
	Port int     `json:"port"`
	TLS  *TLSCfg `json:"tls,omitempty"`
}
type TLSCfg struct {
	SNI        string `json:"sni"`
	VerifyPeer bool   `json:"verify_peer"`
}
type Connect struct {
	Protocol string    `json:"protocol"` // "http"|"tcp"
	Timeouts *Timeouts `json:"timeouts,omitempty"`
}
type Timeouts struct {
	Request string `json:"request,omitempty"` // "5s"
	Idle    string `json:"idle,omitempty"`
}
type Router struct {
	Prefix  string   `json:"prefix"`
	Retries *Retries `json:"retries,omitempty"`
}
type Retries struct {
	Attempts      int    `json:"attempts"`
	PerTryTimeout string `json:"per_try_timeout,omitempty"`
}

var nameRe = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$`)

func Validate(s *ServiceSpec) error {
	if !nameRe.MatchString(s.Name) {
		return fmt.Errorf("name must be DNS-label-ish: %q", s.Name)
	}
	if s.Routing.Host == "" || s.Routing.Port <= 0 || s.Routing.Port > 65535 {
		return errors.New("routing.host and routing.port are required and valid")
	}
	if s.Connect != nil {
		if s.Connect.Protocol != "http" && s.Connect.Protocol != "tcp" {
			return errors.New("connect.protocol must be http or tcp")
		}
		if s.Connect.Timeouts != nil {
			if _, err := time.ParseDuration(zeroOK(s.Connect.Timeouts.Request)); err != nil {
				return fmt.Errorf("connect.timeouts.request invalid: %v", err)
			}
			if _, err := time.ParseDuration(zeroOK(s.Connect.Timeouts.Idle)); err != nil {
				return fmt.Errorf("connect.timeouts.idle invalid: %v", err)
			}
		}
	}
	if s.Router != nil {
		if !strings.HasPrefix(s.Router.Prefix, "/") {
			return errors.New("router.prefix must start with '/' ")
		}
		if s.Router.Retries != nil && (s.Router.Retries.Attempts < 0 || s.Router.Retries.Attempts > 5) {
			return errors.New("router.retries.attempts must be 0..5")
		}
		if s.Router.Retries != nil && s.Router.Retries.PerTryTimeout != "" {
			if _, err := time.ParseDuration(s.Router.Retries.PerTryTimeout); err != nil {
				return fmt.Errorf("router.retries.per_try_timeout invalid: %v", err)
			}
		}
	}
	return nil
}

func zeroOK(s string) string { if s == "" { return "0s" }; return s }

// Helper used by apply layer to default protocol if Connect is nil.
func (s *ServiceSpec) ConnectGetProtocol() string {
	if s.Connect == nil || s.Connect.Protocol == "" {
		return "tcp"
	}
	return s.Connect.Protocol
}
