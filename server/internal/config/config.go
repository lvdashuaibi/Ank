package config

import "os"

type Config struct {
	Port            string
	JWTSecret       string
	StoreDriver     string
	DatabaseURL     string
	AutoMigrate     bool
	AIBaseURL       string
	AIAPIKey        string
	AIModel         string
	BraveAPIKey     string
	BraveSearchURL  string
	BraveCountry    string
	BraveSearchLang string
	JinaAPIKey      string
	JinaReaderURL   string
	AIWebProxyURL   string
	RedisURL        string
}

func Load() Config {
	return Config{
		Port:            getEnv("PORT", "8080"),
		JWTSecret:       getEnv("JWT_SECRET", "flashcard-dev-secret"),
		StoreDriver:     getEnv("STORE_DRIVER", "postgres"),
		DatabaseURL:     getEnv("DATABASE_URL", "postgres://flashcard:flashcard@localhost:5432/flashcard?sslmode=disable"),
		AutoMigrate:     getEnv("AUTO_MIGRATE", "true") != "false",
		AIBaseURL:       getEnv("AI_BASE_URL", ""),
		AIAPIKey:        getEnv("AI_API_KEY", ""),
		AIModel:         getEnv("AI_MODEL", "gpt-4o-mini"),
		BraveAPIKey:     getEnv("BRAVE_API_KEY", ""),
		BraveSearchURL:  getEnv("BRAVE_SEARCH_URL", "https://api.search.brave.com/res/v1/web/search"),
		BraveCountry:    getEnv("BRAVE_COUNTRY", "CN"),
		BraveSearchLang: getEnv("BRAVE_SEARCH_LANG", "zh"),
		JinaAPIKey:      getEnv("JINA_API_KEY", ""),
		JinaReaderURL:   getEnv("JINA_READER_URL", "https://r.jina.ai"),
		AIWebProxyURL:   getEnv("AI_WEB_PROXY_URL", ""),
		RedisURL:        getEnv("REDIS_URL", ""),
	}
}

func getEnv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}
