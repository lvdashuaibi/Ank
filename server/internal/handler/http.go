package handler

import (
	"embed"
	"encoding/json"
	"errors"
	"io/fs"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"github.com/ank/flashcard-server/internal/config"
	"github.com/ank/flashcard-server/internal/model"
	"github.com/ank/flashcard-server/internal/repository"
	"github.com/ank/flashcard-server/internal/service"
)

//go:embed web/**
var webAssets embed.FS

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

	registerWebConsole(router)

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
	protected.GET("/folders", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"items": services.ListFolders(userIDFromContext(c))})
	})
	protected.POST("/folders", func(c *gin.Context) {
		var request model.Folder
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		folder, err := services.CreateFolder(userIDFromContext(c), request)
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusCreated, folder)
	})
	protected.GET("/folders/:id", func(c *gin.Context) {
		folder, err := services.GetFolder(userIDFromContext(c), c.Param("id"))
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, folder)
	})
	protected.PUT("/folders/:id", func(c *gin.Context) {
		var request model.Folder
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		folder, err := services.UpdateFolder(userIDFromContext(c), c.Param("id"), request)
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, folder)
	})
	protected.DELETE("/folders/:id", func(c *gin.Context) {
		if err := services.DeleteFolder(userIDFromContext(c), c.Param("id")); err != nil {
			writeRepoError(c, err)
			return
		}
		c.Status(http.StatusNoContent)
	})
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
	protected.GET("/ai/policies", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"items": services.ListGenerationPolicies(userIDFromContext(c))})
	})
	protected.POST("/ai/policies", func(c *gin.Context) {
		var request model.GenerationPolicy
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		policy, err := services.CreateGenerationPolicy(userIDFromContext(c), request)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusCreated, policy)
	})
	protected.GET("/ai/policies/:id", func(c *gin.Context) {
		policy, err := services.GetGenerationPolicy(userIDFromContext(c), c.Param("id"))
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, policy)
	})
	protected.PUT("/ai/policies/:id", func(c *gin.Context) {
		var request model.GenerationPolicy
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		policy, err := services.UpdateGenerationPolicy(userIDFromContext(c), c.Param("id"), request)
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, policy)
	})
	protected.DELETE("/ai/policies/:id", func(c *gin.Context) {
		if err := services.DeleteGenerationPolicy(userIDFromContext(c), c.Param("id")); err != nil {
			writeRepoError(c, err)
			return
		}
		c.Status(http.StatusNoContent)
	})
	protected.POST("/ai/generate", func(c *gin.Context) {
		var request model.AIGenerateRequest
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		if err := resolveGenerationPolicy(c, services, &request); err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, services.GenerateCards(request))
	})
	protected.POST("/ai/generate-job", func(c *gin.Context) {
		var request model.AIGenerateRequest
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		if err := resolveGenerationPolicy(c, services, &request); err != nil {
			writeRepoError(c, err)
			return
		}
		job, err := services.CreateAIGenerationJob(userIDFromContext(c), request)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusAccepted, job)
	})
	protected.POST("/ai/generate-jobs", func(c *gin.Context) {
		var request model.AIGenerateRequest
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		if err := resolveGenerationPolicy(c, services, &request); err != nil {
			writeRepoError(c, err)
			return
		}
		job, err := services.CreateAIGenerationJob(userIDFromContext(c), request)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusAccepted, job)
	})
	protected.GET("/ai/generate-jobs", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"items": services.ListAIGenerationJobs(userIDFromContext(c))})
	})
	protected.GET("/ai/generate-job/:id", func(c *gin.Context) {
		job, err := services.GetAIGenerationJob(userIDFromContext(c), c.Param("id"))
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, job)
	})
	protected.GET("/ai/generate-jobs/:id", func(c *gin.Context) {
		job, err := services.GetAIGenerationJob(userIDFromContext(c), c.Param("id"))
		if err != nil {
			writeRepoError(c, err)
			return
		}
		c.JSON(http.StatusOK, job)
	})
	protected.POST("/ai/import-file", func(c *gin.Context) {
		file, err := c.FormFile("file")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "missing file"})
			return
		}
		cardCount, _ := strconv.Atoi(c.PostForm("card_count"))
		request := model.AIGenerateRequest{
			Topic:      c.PostForm("topic"),
			CardCount:  cardCount,
			Difficulty: c.PostForm("difficulty"),
			Strategy:   c.PostForm("strategy"),
			CardTypes:  splitCSV(c.PostForm("card_types")),
			PolicyID:   c.PostForm("policy_id"),
		}
		if rawPolicy := strings.TrimSpace(c.PostForm("policy_json")); rawPolicy != "" {
			var policy model.GenerationPolicy
			if err := json.Unmarshal([]byte(rawPolicy), &policy); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid policy_json"})
				return
			}
			request.Policy = &policy
		}
		if err := resolveGenerationPolicy(c, services, &request); err != nil {
			writeRepoError(c, err)
			return
		}
		response, err := services.GenerateCardsFromUpload(request, file)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, response)
	})
	protected.POST("/ai/import-file-job", func(c *gin.Context) {
		file, err := c.FormFile("file")
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "missing file"})
			return
		}
		cardCount, _ := strconv.Atoi(c.PostForm("card_count"))
		request := model.AIGenerateRequest{
			Topic:      c.PostForm("topic"),
			CardCount:  cardCount,
			Difficulty: c.PostForm("difficulty"),
			Strategy:   c.PostForm("strategy"),
			CardTypes:  splitCSV(c.PostForm("card_types")),
			PolicyID:   c.PostForm("policy_id"),
		}
		if rawPolicy := strings.TrimSpace(c.PostForm("policy_json")); rawPolicy != "" {
			var policy model.GenerationPolicy
			if err := json.Unmarshal([]byte(rawPolicy), &policy); err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid policy_json"})
				return
			}
			request.Policy = &policy
		}
		if err := resolveGenerationPolicy(c, services, &request); err != nil {
			writeRepoError(c, err)
			return
		}
		job, err := services.CreateAIGenerationJobFromUpload(userIDFromContext(c), request, file)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusAccepted, job)
	})
	protected.POST("/ai/rewrite-card", func(c *gin.Context) {
		var request model.AIRewriteCardRequest
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, services.RewriteCardWithAI(request))
	})
	protected.POST("/ai/rewrite-batch", func(c *gin.Context) {
		var request model.AIRewriteBatchRequest
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, services.RewriteCardsWithAI(request))
	})
	protected.POST("/ai/chat-cards", func(c *gin.Context) {
		var request model.AICardChatRequest
		if err := c.ShouldBindJSON(&request); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, services.ChatCardsWithAI(request))
	})

	return router
}

func registerWebConsole(router *gin.Engine) {
	assets, err := fs.Sub(webAssets, "web")
	if err != nil {
		panic(err)
	}
	fileServer := http.FileServer(http.FS(assets))
	router.GET("/", func(c *gin.Context) {
		index, readErr := fs.ReadFile(webAssets, "web/index.html")
		if readErr != nil {
			c.String(http.StatusInternalServerError, "web console unavailable")
			return
		}
		c.Data(http.StatusOK, "text/html; charset=utf-8", index)
	})
	router.GET("/web/*filepath", func(c *gin.Context) {
		http.StripPrefix("/web/", fileServer).ServeHTTP(c.Writer, c.Request)
	})
	router.GET("/assets/*filepath", func(c *gin.Context) {
		http.StripPrefix("/", fileServer).ServeHTTP(c.Writer, c.Request)
	})
}

func resolveGenerationPolicy(c *gin.Context, services *service.AppService, request *model.AIGenerateRequest) error {
	if request == nil || request.Policy != nil || strings.TrimSpace(request.PolicyID) == "" {
		return nil
	}
	policy, err := services.GetGenerationPolicy(userIDFromContext(c), request.PolicyID)
	if err != nil {
		return err
	}
	request.Policy = &policy
	return nil
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			result = append(result, part)
		}
	}
	return result
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
