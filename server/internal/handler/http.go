package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"github.com/ank/flashcard-server/internal/config"
	"github.com/ank/flashcard-server/internal/model"
	"github.com/ank/flashcard-server/internal/repository"
	"github.com/ank/flashcard-server/internal/service"
)

type authRequest struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	DisplayName string `json:"display_name"`
}

type reviewRequest struct {
	CardID     string `json:"card_id"`
	Rating     int    `json:"rating"`
	DurationMS int    `json:"duration_ms"`
}

func NewRouter(cfg config.Config, services *service.AppService, logger *zap.Logger) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)
	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(requestLogger(logger))

	router.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "port": cfg.Port})
	})

	api := router.Group("/api/v1")
	api.POST("/auth/register", func(c *gin.Context) {
		var request authRequest
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		user, token, err := services.Register(request.Email, request.Password, request.DisplayName)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusCreated, gin.H{"user": user, "access_token": token})
	})
	api.POST("/auth/login", func(c *gin.Context) {
		var request authRequest
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		user, token, err := services.Login(request.Email, request.Password)
		if err != nil {
			status := http.StatusUnauthorized
			if !errors.Is(err, service.ErrInvalidCredentials) {
				status = http.StatusBadRequest
			}
			c.JSON(status, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"user": user, "access_token": token})
	})

	protected := api.Group("", authMiddleware(services))
	protected.GET("/decks", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"items": services.ListDecks(userIDFromContext(c))})
	})
	protected.POST("/decks", func(c *gin.Context) {
		var request model.Deck
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		deck, err := services.CreateDeck(userIDFromContext(c), request)
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusCreated, deck)
	})
	protected.GET("/decks/:id", func(c *gin.Context) {
		deck, err := services.GetDeck(userIDFromContext(c), c.Param("id"))
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, deck)
	})
	protected.PUT("/decks/:id", func(c *gin.Context) {
		var request model.Deck
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		deck, err := services.UpdateDeck(userIDFromContext(c), c.Param("id"), request)
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, deck)
	})
	protected.DELETE("/decks/:id", func(c *gin.Context) {
		if err := services.DeleteDeck(userIDFromContext(c), c.Param("id")); err != nil {
			writeRepoError(c, err)
			return
		}
		c.Status(http.StatusNoContent)
	})
	protected.GET("/decks/:id/cards", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"items": services.ListCards(userIDFromContext(c), c.Param("id"))})
	})
	protected.POST("/decks/:id/cards", func(c *gin.Context) {
		var request model.Card
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		card, err := services.CreateCard(userIDFromContext(c), c.Param("id"), request)
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusCreated, card)
	})
	protected.GET("/cards/:id", func(c *gin.Context) {
		card, err := services.GetCard(userIDFromContext(c), c.Param("id"))
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, card)
	})
	protected.PUT("/cards/:id", func(c *gin.Context) {
		var request model.Card
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		card, err := services.UpdateCard(userIDFromContext(c), c.Param("id"), request)
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, card)
	})
	protected.DELETE("/cards/:id", func(c *gin.Context) {
		if err := services.DeleteCard(userIDFromContext(c), c.Param("id")); err != nil {
			writeRepoError(c, err)
			return
		}
		c.Status(http.StatusNoContent)
	})
	protected.GET("/review/due", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"items": services.DueCards(userIDFromContext(c), c.Query("deck_id")),
		})
	})
	protected.POST("/review/submit", func(c *gin.Context) {
		var request reviewRequest
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		card, err := services.SubmitReview(
			userIDFromContext(c),
			request.CardID,
			request.Rating,
			request.DurationMS,
		)
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, card)
	})

	protected.POST("/sync/push", func(c *gin.Context) {
		var request model.SyncPushRequest
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, services.SyncPush(userIDFromContext(c), request))
	})
	protected.GET("/sync/pull", func(c *gin.Context) {
		writeJSON(c, http.StatusOK, services.SyncPull(userIDFromContext(c)))
	})
	protected.POST("/ai/generate", func(c *gin.Context) {
		var request model.AIGenerateRequest
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, services.GenerateCards(request))
	})

	return router
}

func requestLogger(logger *zap.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()
		logger.Info(
			"[flashcard_server] request completed",
			zap.String("method", c.Request.Method),
			zap.String("path", c.Request.URL.Path),
			zap.Int("status", c.Writer.Status()),
		)
	}
}

func authMiddleware(services *service.AppService) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		token := strings.TrimPrefix(header, "Bearer ")
		if token == "" || token == header {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing bearer token"})
			return
		}

		claims, err := services.ParseToken(token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			return
		}
		c.Set("user_id", claims.UserID)
		c.Next()
	}
}

func userIDFromContext(c *gin.Context) string {
	value, _ := c.Get("user_id")
	userID, _ := value.(string)
	return userID
}

func writeRepoError(c *gin.Context, err error) {
	if errors.Is(err, repository.ErrNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
}

func writeJSON(c *gin.Context, status int, payload any) {
	body, err := json.Marshal(payload)
	if err != nil {
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{
			"error": "failed to encode response",
		})
		return
	}
	c.Data(status, "application/json; charset=utf-8", body)
}
