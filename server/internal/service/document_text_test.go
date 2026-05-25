package service

import (
	"strings"
	"testing"
)

func TestExtractPlainTextDocument(t *testing.T) {
	doc, err := extractDocumentText("notes.md", "text/markdown", []byte("# 进程\n\n进程是资源分配的基本单位。"))
	if err != nil {
		t.Fatalf("extractDocumentText returned error: %v", err)
	}
	if doc.Title != "notes.md" {
		t.Fatalf("title = %q", doc.Title)
	}
	if !strings.Contains(doc.Text, "进程是资源分配的基本单位") {
		t.Fatalf("text = %q", doc.Text)
	}
	if doc.TextLength == 0 || doc.TextPreview == "" {
		t.Fatalf("expected text metadata, got length=%d preview=%q", doc.TextLength, doc.TextPreview)
	}
}

func TestExtractPDFLiteralText(t *testing.T) {
	pdf := `%PDF-1.7
1 0 obj
<< /Type /Page >>
stream
BT
(Process is the unit of resource allocation.) Tj
(Thread is the unit of CPU scheduling.) Tj
ET
endstream
endobj
%%EOF`
	doc, err := extractDocumentText("os.pdf", "application/pdf", []byte(pdf))
	if err != nil {
		t.Fatalf("extractDocumentText returned error: %v", err)
	}
	if !strings.Contains(doc.Text, "Process is the unit") {
		t.Fatalf("text = %q", doc.Text)
	}
	if doc.PageCount != 1 {
		t.Fatalf("page count = %d", doc.PageCount)
	}
}

func TestExtractUnsupportedDocument(t *testing.T) {
	_, err := extractDocumentText("image.png", "image/png", []byte("abc"))
	if err == nil {
		t.Fatal("expected unsupported document error")
	}
}
