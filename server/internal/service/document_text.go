package service

import (
	"bytes"
	"encoding/hex"
	"errors"
	"fmt"
	"mime/multipart"
	"path/filepath"
	"regexp"
	"strings"
	"unicode/utf16"
	"unicode/utf8"
)

const maxAIImportBytes = 8 * 1024 * 1024

var (
	errUnsupportedDocument = errors.New("unsupported document type")
	errEmptyDocument       = errors.New("document has no extractable text")
)

type extractedDocument struct {
	Title       string
	MimeType    string
	Text        string
	TextPreview string
	TextLength  int
	PageCount   int
}

func extractDocumentFromUpload(header *multipart.FileHeader) (extractedDocument, error) {
	if header == nil {
		return extractedDocument{}, fmt.Errorf("missing file")
	}
	if header.Size > maxAIImportBytes {
		return extractedDocument{}, fmt.Errorf("file is too large")
	}
	file, err := header.Open()
	if err != nil {
		return extractedDocument{}, err
	}
	defer file.Close()

	buffer := bytes.NewBuffer(make([]byte, 0, header.Size))
	if _, err := buffer.ReadFrom(file); err != nil {
		return extractedDocument{}, err
	}
	return extractDocumentText(header.Filename, header.Header.Get("Content-Type"), buffer.Bytes())
}

func extractDocumentText(filename, mimeType string, data []byte) (extractedDocument, error) {
	if len(bytes.TrimSpace(data)) == 0 {
		return extractedDocument{}, errEmptyDocument
	}

	ext := strings.ToLower(filepath.Ext(filename))
	title := strings.TrimSpace(filepath.Base(filename))
	if title == "." || title == "" {
		title = "导入文件"
	}

	var (
		text      string
		pageCount int
		err       error
	)
	switch ext {
	case ".txt", ".md", ".markdown":
		text, err = extractPlainText(data)
	case ".pdf":
		text, pageCount, err = extractPDFText(data)
	default:
		if strings.Contains(mimeType, "pdf") {
			text, pageCount, err = extractPDFText(data)
		} else if strings.HasPrefix(mimeType, "text/") {
			text, err = extractPlainText(data)
		} else {
			return extractedDocument{}, errUnsupportedDocument
		}
	}
	if err != nil {
		return extractedDocument{}, err
	}
	text = normalizeExtractedText(text)
	if text == "" {
		return extractedDocument{}, errEmptyDocument
	}
	return extractedDocument{
		Title:       title,
		MimeType:    mimeType,
		Text:        text,
		TextPreview: previewText(text, 420),
		TextLength:  utf8.RuneCountInString(text),
		PageCount:   pageCount,
	}, nil
}

func extractPlainText(data []byte) (string, error) {
	if !utf8.Valid(data) {
		return "", fmt.Errorf("only UTF-8 text files are supported")
	}
	return string(data), nil
}

func extractPDFText(data []byte) (string, int, error) {
	if !bytes.HasPrefix(bytes.TrimSpace(data), []byte("%PDF")) {
		return "", 0, fmt.Errorf("invalid PDF file")
	}
	raw := string(data)
	pageCount := regexp.MustCompile(`/Type\s*/Page\b`).FindAllStringIndex(raw, -1)

	var parts []string
	literalRe := regexp.MustCompile(`\((?:\\.|[^\\)]){2,}\)`)
	for _, match := range literalRe.FindAllString(raw, -1) {
		text := decodePDFLiteralString(match[1 : len(match)-1])
		if isUsefulPDFText(text) {
			parts = append(parts, text)
		}
	}

	hexRe := regexp.MustCompile(`<([0-9A-Fa-f\s]{8,})>`)
	for _, match := range hexRe.FindAllStringSubmatch(raw, -1) {
		text := decodePDFHexString(match[1])
		if isUsefulPDFText(text) {
			parts = append(parts, text)
		}
	}

	text := normalizeExtractedText(strings.Join(parts, "\n"))
	if text == "" {
		return "", len(pageCount), fmt.Errorf("PDF does not contain selectable text; scanned PDFs need OCR")
	}
	return text, len(pageCount), nil
}

func decodePDFLiteralString(input string) string {
	var builder strings.Builder
	for i := 0; i < len(input); i++ {
		ch := input[i]
		if ch != '\\' || i == len(input)-1 {
			builder.WriteByte(ch)
			continue
		}
		i++
		switch input[i] {
		case 'n':
			builder.WriteByte('\n')
		case 'r':
			builder.WriteByte('\r')
		case 't':
			builder.WriteByte('\t')
		case 'b', 'f':
		case '(', ')', '\\':
			builder.WriteByte(input[i])
		default:
			if input[i] >= '0' && input[i] <= '7' {
				end := i + 1
				for end < len(input) && end < i+3 && input[end] >= '0' && input[end] <= '7' {
					end++
				}
				value := 0
				for _, digit := range input[i:end] {
					value = value*8 + int(digit-'0')
				}
				builder.WriteByte(byte(value))
				i = end - 1
			} else {
				builder.WriteByte(input[i])
			}
		}
	}
	return builder.String()
}

func decodePDFHexString(input string) string {
	compact := strings.Join(strings.Fields(input), "")
	if len(compact)%2 == 1 {
		compact += "0"
	}
	data, err := hex.DecodeString(compact)
	if err != nil || len(data) == 0 {
		return ""
	}
	if len(data) >= 2 && data[0] == 0xFE && data[1] == 0xFF {
		units := make([]uint16, 0, (len(data)-2)/2)
		for i := 2; i+1 < len(data); i += 2 {
			units = append(units, uint16(data[i])<<8|uint16(data[i+1]))
		}
		return string(utf16.Decode(units))
	}
	if utf8.Valid(data) {
		return string(data)
	}
	return ""
}

func isUsefulPDFText(text string) bool {
	text = strings.TrimSpace(text)
	if utf8.RuneCountInString(text) < 2 {
		return false
	}
	letters := 0
	for _, r := range text {
		if r > 127 || (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			letters++
		}
	}
	return letters >= 2
}

func normalizeExtractedText(input string) string {
	input = strings.ReplaceAll(input, "\r\n", "\n")
	input = strings.ReplaceAll(input, "\r", "\n")
	lines := strings.Split(input, "\n")
	out := make([]string, 0, len(lines))
	previousBlank := false
	for _, line := range lines {
		line = strings.Join(strings.Fields(line), " ")
		if line == "" {
			if !previousBlank && len(out) > 0 {
				out = append(out, "")
			}
			previousBlank = true
			continue
		}
		out = append(out, line)
		previousBlank = false
	}
	return strings.TrimSpace(strings.Join(out, "\n"))
}

func previewText(input string, limit int) string {
	if limit <= 0 {
		return ""
	}
	runes := []rune(strings.TrimSpace(input))
	if len(runes) <= limit {
		return string(runes)
	}
	return string(runes[:limit]) + "..."
}
