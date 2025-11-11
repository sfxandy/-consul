package consulx

import (
	"context"
	"errors"
	"time"

	"github.com/hashicorp/consul/api"
)

var ErrLockHeld = errors.New("lock held by another worker")

type Lock struct {
	sid  string
	key  string
	kv   *api.KV
	sv   *api.Session
	stop chan struct{}
}

func Acquire(ctx context.Context, cli *api.Client, key, owner string, ttl time.Duration, attempts int) (*Lock, error) {
	sv := cli.Session()
	kv := cli.KV()

	sid, _, err := sv.Create(&api.SessionEntry{
		TTL:      ttl.String(),
		Behavior: api.SessionBehaviorDelete,
		Name:     "svc-handler:" + key,
	}, nil)
	if err != nil {
		return nil, err
	}

	p := &api.KVPair{Key: key, Value: []byte(owner), Session: sid}
	for i := 0; i < attempts; i++ {
		ok, _, err := kv.Acquire(p, nil)
		if err != nil {
			_ = sv.Destroy(sid, nil)
			return nil, err
		}
		if ok {
			lock := &Lock{sid: sid, key: key, kv: kv, sv: sv, stop: make(chan struct{})}
			go lock.renew(ttl / 2)
			return lock, nil
		}
		select {
		case <-ctx.Done():
			_ = sv.Destroy(sid, nil)
			return nil, ctx.Err()
		case <-time.After(backoff(i)):
		}
	}
	_ = sv.Destroy(sid, nil)
	return nil, ErrLockHeld
}

func (l *Lock) renew(every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-l.stop:
			return
		case <-t.C:
			_, _, _ = l.sv.Renew(l.sid, nil)
		}
	}
}

func (l *Lock) Release(ctx context.Context) error {
	close(l.stop)
	_, _, _ = l.kv.Release(&api.KVPair{Key: l.key, Session: l.sid}, nil)
	_, err := l.sv.Destroy(l.sid, nil)
	return err
}

func backoff(i int) time.Duration {
	d := 200*time.Millisecond << i
	if d > 3*time.Second {
		d = 3 * time.Second
	}
	return d
}
