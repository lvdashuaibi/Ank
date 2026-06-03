package service

import (
	"bytes"
	"compress/zlib"
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

func TestExtractMarkdownDocumentWithImages(t *testing.T) {
	markdown := strings.Join([]string{
		"# 第一章 教育目的",
		"",
		"教育目的规定人才培养方向。",
		"",
		"![教育目的结构图](images/aims.png)",
		"",
		"![远程示例](https://example.com/chart.png)",
	}, "\n")

	doc, err := extractDocumentText("education.md", "text/markdown", []byte(markdown))
	if err != nil {
		t.Fatalf("extractDocumentText returned error: %v", err)
	}
	if doc.ImageCount != 2 {
		t.Fatalf("expected two image references, got %d", doc.ImageCount)
	}
	if len(doc.Images) != 2 {
		t.Fatalf("expected image metadata, got %+v", doc.Images)
	}
	if doc.Images[0].Alt != "教育目的结构图" || doc.Images[0].Source != "images/aims.png" {
		t.Fatalf("unexpected first image: %+v", doc.Images[0])
	}
	if !strings.Contains(doc.Text, "[图片: 教育目的结构图") {
		t.Fatalf("expected image placeholder in extracted text, got %q", doc.Text)
	}
	if !strings.Contains(doc.TextPreview, "图片") {
		t.Fatalf("expected preview to mention image placeholder, got %q", doc.TextPreview)
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

func TestExtractPDFArrayTextOperator(t *testing.T) {
	pdf := `%PDF-1.7
1 0 obj
<< /Type /Page >>
stream
BT
[(Education aims ) 120 (guide learner development.)] TJ
[(Teaching principles ) 90 (guide instruction.)] TJ
ET
endstream
endobj
%%EOF`
	doc, err := extractDocumentText("education.pdf", "application/pdf", []byte(pdf))
	if err != nil {
		t.Fatalf("extractDocumentText returned error: %v", err)
	}
	if !strings.Contains(doc.Text, "Education aims guide learner development") {
		t.Fatalf("expected combined TJ text, got %q", doc.Text)
	}
	if !strings.Contains(doc.Text, "Teaching principles guide instruction") {
		t.Fatalf("expected second TJ text, got %q", doc.Text)
	}
}

func TestExtractPDFCompressedTextStream(t *testing.T) {
	var compressed bytes.Buffer
	writer := zlib.NewWriter(&compressed)
	if _, err := writer.Write([]byte("BT\n[(Education aims ) 120 (guide learners.)] TJ\nET")); err != nil {
		t.Fatalf("write zlib stream: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close zlib stream: %v", err)
	}

	pdf := append([]byte(`%PDF-1.7
1 0 obj
<< /Type /Page >>
endobj
2 0 obj
<< /Length 0 /Filter /FlateDecode >>
stream
`), compressed.Bytes()...)
	pdf = append(pdf, []byte(`
endstream
endobj
%%EOF`)...)

	doc, err := extractDocumentText("education.pdf", "application/pdf", pdf)
	if err != nil {
		t.Fatalf("extractDocumentText returned error: %v", err)
	}
	if !strings.Contains(doc.Text, "Education aims guide learners") {
		t.Fatalf("expected text from compressed stream, got %q", doc.Text)
	}
}

func TestExtractUnsupportedDocument(t *testing.T) {
	_, err := extractDocumentText("image.png", "image/png", []byte("abc"))
	if err == nil {
		t.Fatal("expected unsupported document error")
	}
}
