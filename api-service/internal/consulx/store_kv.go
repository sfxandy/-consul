package consulx

import (
	"context"
	"encoding/json"

	"github.com/hashicorp/consul/api"
	"github.com/yourorg/svc-handler/internal/model"
)

func PutDesired(ctx context.Context, cli *api.Client, key string, spec *model.ServiceSpec) error {
	b, _ := json.Marshal(spec)
	_, err := cli.KV().Put(&api.KVPair{Key: key, Value: b}, nil)
	return err
}
func GetDesired(ctx context.Context, cli *api.Client, key string) (*model.ServiceSpec, bool, error) {
	kvp, _, err := cli.KV().Get(key, nil)
	if err != nil {
		return nil, false, err
	}
	if kvp == nil {
		return nil, false, nil
	}
	var s model.ServiceSpec
	if err := json.Unmarshal(kvp.Value, &s); err != nil {
		return nil, false, err
	}
	return &s, true, nil
}
func DelDesired(ctx context.Context, cli *api.Client, key string) error {
	_, err := cli.KV().Delete(key, nil)
	return err
}
