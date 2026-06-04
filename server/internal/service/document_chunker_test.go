package service

import (
	"fmt"
	"testing"

	"github.com/ank/flashcard-server/internal/model"
)

func TestSelectDocumentChunksForGenerationBalancesLongDocuments(t *testing.T) {
	chunks := make([]documentChunk, 12)
	for i := range chunks {
		chunks[i] = documentChunk{
			Index:          i,
			HeadingPath:    fmt.Sprintf("章节 %d", i+1),
			SourceLocation: fmt.Sprintf("章节 %d", i+1),
			Text:           fmt.Sprintf("内容 %d", i+1),
		}
	}

	selected := selectDocumentChunksForGeneration(chunks, 16, model.GenerationPolicy{
		CoverageMode:       "balanced",
		MaxCardsPerChunk:   4,
		MaxCardsTotal:      16,
		MaxAnswerChars:     120,
		AtomicityLevel:     "strict",
		PreferredCardTypes: []string{"basic"},
	})

	if len(selected) != 4 {
		t.Fatalf("expected 4 selected chunks, got %d", len(selected))
	}
	indexes := []int{selected[0].Index, selected[1].Index, selected[2].Index, selected[3].Index}
	if indexes[0] != 0 || indexes[3] != 11 {
		t.Fatalf("expected balanced selection to include first and last chunks, got %v", indexes)
	}
	if indexes[1] <= 0 || indexes[2] <= indexes[1] || indexes[2] >= 11 {
		t.Fatalf("expected middle chunks to be spread out, got %v", indexes)
	}
}
