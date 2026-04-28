package main

import (
	"log"
	"strings"

	"go.uber.org/zap"

	"github.com/ank/flashcard-server/internal/config"
	"github.com/ank/flashcard-server/internal/handler"
	"github.com/ank/flashcard-server/internal/repository"
	"github.com/ank/flashcard-server/internal/service"
)

func main() {
	cfg := config.Load()

	logger, err := zap.NewProduction()
	if err != nil {
		log.Fatalf("init logger: %v", err)
	}
	defer func() {
		_ = logger.Sync()
	}()

	var store repository.Store
	if strings.EqualFold(cfg.StoreDriver, "postgres") {
		store, err = repository.NewPostgresStore(cfg.DatabaseURL, cfg.AutoMigrate)
		if err != nil {
			logger.Fatal("[flashcard_server] init postgres store failed", zap.Error(err))
		}
	} else {
		store = repository.NewMemoryStore()
	}
	defer func() {
		_ = store.Close()
	}()

	services := service.NewAppService(cfg, store, logger)
	router := handler.NewRouter(cfg, services, logger)

	logger.Info(
		"[flashcard_server] starting http server",
		zap.String("addr", ":"+cfg.Port),
	)

	if err := router.Run(":" + cfg.Port); err != nil {
		logger.Fatal("[flashcard_server] server exited", zap.Error(err))
	}
}
