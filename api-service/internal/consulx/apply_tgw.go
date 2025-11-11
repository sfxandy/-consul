package consulx

import (
	"context"
	"fmt"

	"github.com/hashicorp/consul/api"
	"github.com/yourorg/svc-handler/internal/model"
)

// NOTE: Adjust to match your organization's TGW static mapping approach.

func UpsertServiceDefaults(ctx context.Context, cli *api.Client, spec *model.ServiceSpec) error {
	entry := &api.ServiceConfigEntry{
		Kind:     api.ServiceDefaults,
		Name:     spec.Name,
		Protocol: spec.ConnectGetProtocol(),
	}
	_, _, err := cli.ConfigEntries().Set(entry, nil)
	return err
}

func UpsertTGWBinding(ctx context.Context, cli *api.Client, tgwService string, spec *model.ServiceSpec) error {
	// Read existing TGW entry, update (idempotent)
	ce, _, err := cli.ConfigEntries().Get(api.TerminatingGateway, tgwService, &api.QueryOptions{RequireConsistent: true})
	if err != nil && !isNotFound(err) && ce == nil {
		// If TGW entry doesn't exist, create a fresh one
		// Proceed to create below.
	}
	var tgw *api.TerminatingGatewayConfigEntry
	if ce != nil {
		if v, ok := ce.(*api.TerminatingGatewayConfigEntry); ok {
			tgw = v
		}
	}
	if tgw == nil {
		tgw = &api.TerminatingGatewayConfigEntry{Kind: api.TerminatingGateway, Name: tgwService}
	}
	// Replace or insert our service mapping. We encode destination in Meta (pattern varies by org).
	up := api.LinkedService{Name: spec.Name}
	found := false
	for i, ls := range tgw.Services {
		if ls.Name == spec.Name {
			tgw.Services[i] = up
			found = true
			break
		}
	}
	if !found {
		tgw.Services = append(tgw.Services, up)
	}
	_, _, err = cli.ConfigEntries().Set(tgw, nil)
	return err
}

func UpsertServiceRouter(ctx context.Context, cli *api.Client, spec *model.ServiceSpec) error {
	if spec.Router == nil {
		return nil
	}
	router := &api.ServiceRouterConfigEntry{
		Kind: api.ServiceRouter,
		Name: spec.Name,
		Routes: []api.ServiceRoute{{
			Match: &api.ServiceRouteMatch{
				Http: &api.ServiceRouteHTTPMatch{PathPrefix: spec.Router.Prefix},
			},
		}},
	}
	_, _, err := cli.ConfigEntries().Set(router, nil)
	return err
}

func DeleteServiceRouter(ctx context.Context, cli *api.Client, name string) error {
	ok, _, err := cli.ConfigEntries().Delete(api.ServiceRouter, name, nil)
	if err != nil {
		return err
	}
	_ = ok
	return nil
}

func DeleteTGWBinding(ctx context.Context, cli *api.Client, tgwService, name string) error {
	ce, _, err := cli.ConfigEntries().Get(api.TerminatingGateway, tgwService, &api.QueryOptions{RequireConsistent: true})
	if err != nil {
		return err
	}
	tgw, _ := ce.(*api.TerminatingGatewayConfigEntry)
	if tgw == nil {
		return nil // not found
	}
	filtered := tgw.Services[:0]
	for _, ls := range tgw.Services {
		if ls.Name != name {
			filtered = append(filtered, ls)
		}
	}
	tgw.Services = filtered
	_, _, err = cli.ConfigEntries().Set(tgw, nil)
	return err
}

func DeleteServiceDefaults(ctx context.Context, cli *api.Client, name string) error {
	ok, _, err := cli.ConfigEntries().Delete(api.ServiceDefaults, name, nil)
	if err != nil {
		return err
	}
	_ = ok
	return nil
}

type Observed struct {
	ServiceDefaults map[string]any `json:"service-defaults"`
	TGW             map[string]any `json:"tgw"`
	ServiceRouter   map[string]any `json:"service-router,omitempty"`
}

func Observe(ctx context.Context, cli *api.Client, tgwService string, spec *model.ServiceSpec) (*Observed, error) {
	obs := &Observed{
		ServiceDefaults: map[string]any{"present": false},
		TGW:             map[string]any{"present": false},
	}
	if ce, _, _ := cli.ConfigEntries().Get(api.ServiceDefaults, spec.Name, &api.QueryOptions{RequireConsistent: true}); ce != nil {
		obs.ServiceDefaults["present"] = true
	}
	if ce, _, _ := cli.ConfigEntries().Get(api.TerminatingGateway, tgwService, &api.QueryOptions{RequireConsistent: true}); ce != nil {
		if tgw, _ := ce.(*api.TerminatingGatewayConfigEntry); tgw != nil {
			for _, ls := range tgw.Services {
				if ls.Name == spec.Name {
					obs.TGW["present"] = true
					break
				}
			}
		}
	}
	if spec.Router != nil {
		if ce, _, _ := cli.ConfigEntries().Get(api.ServiceRouter, spec.Name, &api.QueryOptions{RequireConsistent: true}); ce != nil {
			obs.ServiceRouter = map[string]any{"present": true}
		} else {
			obs.ServiceRouter = map[string]any{"present": false}
		}
	}
	return obs, nil
}

func Verify(ctx context.Context, cli *api.Client, tgwService string, spec *model.ServiceSpec) error {
	obs, err := Observe(ctx, cli, tgwService, spec)
	if err != nil {
		return err
	}
	if !obs.ServiceDefaults["present"].(bool) || !obs.TGW["present"].(bool) {
		return fmt.Errorf("verify failed: missing components (defaults:%v tgw:%v)", obs.ServiceDefaults["present"], obs.TGW["present"]) }
	if spec.Router != nil && !obs.ServiceRouter["present"].(bool) {
		return fmt.Errorf("verify failed: missing service-router")
	}
	return nil
}

func isNotFound(err error) bool { return false } // placeholder if you add typed errors later
