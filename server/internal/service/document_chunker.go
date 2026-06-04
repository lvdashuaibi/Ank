package service

import (
	"fmt"
	"math"
	"regexp"
	"strings"
	"unicode/utf8"

	"github.com/ank/flashcard-server/internal/model"
)

const (
	targetDocumentChunkRunes = 3000
	hardDocumentChunkRunes   = 5000
)

var markdownHeadingRe = regexp.MustCompile(`^(#{1,6})\s+(.+)$`)

type documentChunk struct {
	Index          int
	HeadingPath    string
	Text           string
	SourceLocation string
	PageStart      int
	PageEnd        int
}

func chunkDocument(doc extractedDocument, policy model.GenerationPolicy) []documentChunk {
	text := strings.TrimSpace(doc.Text)
	if text == "" {
		return nil
	}
	if strings.EqualFold(policy.SplitStrategy, "by_heading") {
		if chunks := chunkMarkdownByHeading(text); len(chunks) > 0 {
			return chunks
		}
	}
	return chunkBySize(text)
}

func selectDocumentChunksForGeneration(chunks []documentChunk, cardBudget int, policy model.GenerationPolicy) []documentChunk {
	if len(chunks) == 0 || cardBudget <= 0 {
		return nil
	}
	maxCardsPerChunk := policy.MaxCardsPerChunk
	if maxCardsPerChunk <= 0 {
		maxCardsPerChunk = 1
	}
	maxChunkCount := int(math.Ceil(float64(cardBudget) / float64(maxCardsPerChunk)))
	if maxChunkCount <= 0 || maxChunkCount >= len(chunks) || !strings.EqualFold(strings.TrimSpace(policy.CoverageMode), "balanced") {
		return chunks
	}
	if maxChunkCount == 1 {
		return chunks[:1]
	}

	selected := make([]documentChunk, 0, maxChunkCount)
	seen := map[int]struct{}{}
	step := float64(len(chunks)-1) / float64(maxChunkCount-1)
	for i := 0; i < maxChunkCount; i++ {
		index := int(math.Round(float64(i) * step))
		if index < 0 {
			index = 0
		}
		if index >= len(chunks) {
			index = len(chunks) - 1
		}
		if _, ok := seen[index]; ok {
			continue
		}
		seen[index] = struct{}{}
		selected = append(selected, chunks[index])
	}
	for index := 0; len(selected) < maxChunkCount && index < len(chunks); index++ {
		if _, ok := seen[index]; ok {
			continue
		}
		seen[index] = struct{}{}
		selected = append(selected, chunks[index])
	}
	return selected
}

func chunkMarkdownByHeading(text string) []documentChunk {
	lines := strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n")
	headingStack := make([]string, 0, 6)
	chunks := make([]documentChunk, 0)
	var body []string
	currentHeading := ""

	flush := func() {
		chunkText := strings.TrimSpace(strings.Join(body, "\n"))
		if chunkText == "" || currentHeading == "" {
			body = nil
			return
		}
		chunks = append(chunks, documentChunk{
			Index:          len(chunks),
			HeadingPath:    currentHeading,
			Text:           chunkText,
			SourceLocation: currentHeading,
		})
		body = nil
	}

	for _, line := range lines {
		if match := markdownHeadingRe.FindStringSubmatch(strings.TrimSpace(line)); match != nil {
			flush()
			level := len(match[1])
			title := strings.TrimSpace(match[2])
			if len(headingStack) >= level {
				headingStack = headingStack[:level-1]
			}
			for len(headingStack) < level-1 {
				headingStack = append(headingStack, "")
			}
			headingStack = append(headingStack, title)
			currentHeading = strings.Join(compactStrings(headingStack), " / ")
			continue
		}
		body = append(body, line)
	}
	flush()

	if len(chunks) == 0 {
		return nil
	}
	return splitOversizedChunks(chunks)
}

func chunkBySize(text string) []documentChunk {
	paragraphs := strings.Split(text, "\n\n")
	chunks := make([]documentChunk, 0)
	var current []string
	currentRunes := 0
	flush := func() {
		chunkText := strings.TrimSpace(strings.Join(current, "\n\n"))
		if chunkText == "" {
			current = nil
			currentRunes = 0
			return
		}
		chunks = append(chunks, documentChunk{
			Index:          len(chunks),
			HeadingPath:    fmt.Sprintf("片段 %d", len(chunks)+1),
			Text:           chunkText,
			SourceLocation: fmt.Sprintf("chunk %d", len(chunks)+1),
		})
		current = nil
		currentRunes = 0
	}

	for _, paragraph := range paragraphs {
		paragraph = strings.TrimSpace(paragraph)
		if paragraph == "" {
			continue
		}
		nextRunes := utf8.RuneCountInString(paragraph)
		if currentRunes > 0 && currentRunes+nextRunes > targetDocumentChunkRunes {
			flush()
		}
		current = append(current, paragraph)
		currentRunes += nextRunes
		if currentRunes >= hardDocumentChunkRunes {
			flush()
		}
	}
	flush()
	return splitOversizedChunks(chunks)
}

func splitOversizedChunks(chunks []documentChunk) []documentChunk {
	out := make([]documentChunk, 0, len(chunks))
	for _, chunk := range chunks {
		if utf8.RuneCountInString(chunk.Text) <= hardDocumentChunkRunes {
			chunk.Index = len(out)
			out = append(out, chunk)
			continue
		}
		runes := []rune(chunk.Text)
		for start := 0; start < len(runes); start += targetDocumentChunkRunes {
			end := start + targetDocumentChunkRunes
			if end > len(runes) {
				end = len(runes)
			}
			part := chunk
			part.Index = len(out)
			part.Text = strings.TrimSpace(string(runes[start:end]))
			part.SourceLocation = fmt.Sprintf("%s.%d", chunk.SourceLocation, len(out)+1)
			out = append(out, part)
		}
	}
	return out
}
