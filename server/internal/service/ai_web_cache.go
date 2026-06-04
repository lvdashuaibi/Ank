package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"sync"
	"time"

	"github.com/ank/flashcard-server/internal/config"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
)

type aiToolCache interface {
	Get(ctx context.Context, key string) (string, bool)
	Set(ctx context.Context, key string, value string, ttl time.Duration)
}

type memoryAIToolCache struct {
	mu      sync.Mutex
	entries map[string]memoryAIToolCacheEntry
}

type memoryAIToolCacheEntry struct {
	value     string
	expiresAt time.Time
}

func newMemoryAIToolCache() *memoryAIToolCache {
	return &memoryAIToolCache{entries: map[string]memoryAIToolCacheEntry{}}
}

func (c *memoryAIToolCache) Get(_ context.Context, key string) (string, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	entry, ok := c.entries[key]
	if !ok || (!entry.expiresAt.IsZero() && time.Now().After(entry.expiresAt)) {
		delete(c.entries, key)
		return "", false
	}
	return entry.value, true
}

func (c *memoryAIToolCache) Set(_ context.Context, key string, value string, ttl time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	expiresAt := time.Time{}
	if ttl > 0 {
		expiresAt = time.Now().Add(ttl)
	}
	c.entries[key] = memoryAIToolCacheEntry{value: value, expiresAt: expiresAt}
}

type redisAIToolCache struct {
	client *redis.Client
	logger *zap.Logger
}

func newAIToolCache(cfg config.Config, logger *zap.Logger) aiToolCache {
	if cfg.RedisURL == "" {
		return newMemoryAIToolCache()
	}
	options, err := redis.ParseURL(cfg.RedisURL)
	if err != nil {
		if logger != nil {
			logger.Warn("[flashcard_server] invalid REDIS_URL; falling back to memory ai cache", zap.Error(err))
		}
		return newMemoryAIToolCache()
	}
	client := redis.NewClient(options)
	ctx, cancel := context.WithTimeout(context.Background(), 800*time.Millisecond)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		if logger != nil {
			logger.Warn("[flashcard_server] redis unavailable; falling back to memory ai cache", zap.Error(err))
		}
		_ = client.Close()
		return newMemoryAIToolCache()
	}
	return &redisAIToolCache{client: client, logger: logger}
}

func (c *redisAIToolCache) Get(ctx context.Context, key string) (string, bool) {
	value, err := c.client.Get(ctx, key).Result()
	if err != nil {
		if err != redis.Nil && c.logger != nil {
			c.logger.Warn("[flashcard_server] redis ai cache get failed", zap.Error(err))
		}
		return "", false
	}
	return value, true
}

func (c *redisAIToolCache) Set(ctx context.Context, key string, value string, ttl time.Duration) {
	if err := c.client.Set(ctx, key, value, ttl).Err(); err != nil && c.logger != nil {
		c.logger.Warn("[flashcard_server] redis ai cache set failed", zap.Error(err))
	}
}

func aiCacheKey(parts ...string) string {
	hash := sha256.New()
	for _, part := range parts {
		_, _ = hash.Write([]byte(part))
		_, _ = hash.Write([]byte{0})
	}
	return "ai-web:" + hex.EncodeToString(hash.Sum(nil))
}
