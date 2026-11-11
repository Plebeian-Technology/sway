package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type mockRunner struct {
	mu       sync.Mutex
	handlers []func(ctx context.Context, name string, args ...string) ([]byte, []byte, error)
	calls    [][]string
}

func (m *mockRunner) Run(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
	m.mu.Lock()
	call := append([]string{name}, args...)
	m.calls = append(m.calls, call)

	var handler func(ctx context.Context, name string, args ...string) ([]byte, []byte, error)
	if len(m.handlers) > 0 {
		handler = m.handlers[0]
		m.handlers = m.handlers[1:]
	}
	m.mu.Unlock()

	if handler != nil {
		return handler(ctx, name, args...)
	}
	return nil, nil, errors.New("unexpected command execution")
}

func (m *mockRunner) addHandler(h func(ctx context.Context, name string, args ...string) ([]byte, []byte, error)) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.handlers = append(m.handlers, h)
}

func setupTestServer(t *testing.T, runner CommandRunner, allowedRoot string, concurrency int) *Server {
	t.Helper()
	cfg := Config{
		Port:           "8085",
		AllowedRoot:    allowedRoot,
		ContainerRoot:  defaultContainerRoot,
		Concurrency:    concurrency,
		Timeout:        5 * time.Second,
		MinNativeChars: 50,
		OCRDPI:         300,
		MaxOCRPages:    50,
	}
	server, err := NewServer(cfg, runner)
	if err != nil {
		t.Fatalf("failed to create server: %v", err)
	}
	return server
}

func TestUp(t *testing.T) {
	runner := &mockRunner{}
	server := setupTestServer(t, runner, t.TempDir(), 1)

	req := httptest.NewRequest(http.MethodGet, "/up", nil)
	rec := httptest.NewRecorder()

	server.Routes().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}
	if body := strings.TrimSpace(rec.Body.String()); body != "ok" {
		t.Fatalf("expected body 'ok', got %q", body)
	}
}

func TestExtract_PathValidation(t *testing.T) {
	allowedDir := t.TempDir()
	outsideDir := t.TempDir()

	validPDF := filepath.Join(allowedDir, "valid.pdf")
	if err := os.WriteFile(validPDF, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}

	insideSubdir := filepath.Join(allowedDir, "subdir")
	if err := os.Mkdir(insideSubdir, 0755); err != nil {
		t.Fatal(err)
	}

	insideTextFile := filepath.Join(allowedDir, "not_a_pdf.txt")
	if err := os.WriteFile(insideTextFile, []byte("plain text"), 0644); err != nil {
		t.Fatal(err)
	}

	insideSqlite := filepath.Join(allowedDir, "database.sqlite3")
	if err := os.WriteFile(insideSqlite, []byte("sqlite binary data"), 0644); err != nil {
		t.Fatal(err)
	}

	insideNonExistent := filepath.Join(allowedDir, "does_not_exist.pdf")

	outsidePDF := filepath.Join(outsideDir, "outside.pdf")
	if err := os.WriteFile(outsidePDF, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}

	symlinkToOutside := filepath.Join(allowedDir, "symlink_outside.pdf")
	if err := os.Symlink(outsidePDF, symlinkToOutside); err != nil {
		t.Fatal(err)
	}

	tests := []struct {
		name         string
		path         string
		expectCode   int
		expectErrMsg string
	}{
		{
			name:       "empty path",
			path:       "",
			expectCode: http.StatusBadRequest,
		},
		{
			name:       "outside allowed root",
			path:       outsidePDF,
			expectCode: http.StatusBadRequest,
		},
		{
			name:       "non-existent file inside allowed root",
			path:       insideNonExistent,
			expectCode: http.StatusBadRequest,
		},
		{
			name:         "directory inside allowed root",
			path:         insideSubdir,
			expectCode:   http.StatusBadRequest,
			expectErrMsg: "is not a regular file",
		},
		{
			name:         "non-.pdf text extension",
			path:         insideTextFile,
			expectCode:   http.StatusBadRequest,
			expectErrMsg: "must have a .pdf extension",
		},
		{
			name:         "non-.pdf sqlite extension",
			path:         insideSqlite,
			expectCode:   http.StatusBadRequest,
			expectErrMsg: "must have a .pdf extension",
		},
		{
			name:       "relative traversal",
			path:       filepath.Join(allowedDir, "../outside.pdf"),
			expectCode: http.StatusBadRequest,
		},
		{
			name:       "symlink target outside allowed root",
			path:       symlinkToOutside,
			expectCode: http.StatusBadRequest,
		},
		{
			name:       "absolute non-existent path outside root",
			path:       "/etc/passwd",
			expectCode: http.StatusBadRequest,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			runner := &mockRunner{}
			server := setupTestServer(t, runner, allowedDir, 1)

			reqBody, _ := json.Marshal(ExtractRequest{
				PDFPath: tc.path,
			})
			req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()

			server.Routes().ServeHTTP(rec, req)

			if rec.Code != tc.expectCode {
				t.Fatalf("expected status %d, got %d (body: %s)", tc.expectCode, rec.Code, rec.Body.String())
			}

			var errResp ErrorResponse
			if err := json.Unmarshal(rec.Body.Bytes(), &errResp); err != nil {
				t.Fatalf("expected JSON error response: %v", err)
			}
			if errResp.Error == "" {
				t.Fatal("expected non-empty error message")
			}
			if tc.expectErrMsg != "" && !strings.Contains(errResp.Error, tc.expectErrMsg) {
				t.Fatalf("expected error containing %q, got %q", tc.expectErrMsg, errResp.Error)
			}
		})
	}
}

func TestExtract_NativeTextSuccess(t *testing.T) {
	allowedDir := t.TempDir()
	pdfFile := filepath.Join(allowedDir, "bill.pdf")
	if err := os.WriteFile(pdfFile, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}

	runner := &mockRunner{}
	nativeText := "This is a document with well over fifty characters of native text extracted by mutool draw txt command."
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		if name != "mutool" || args[0] != "draw" || args[1] != "-F" || args[2] != "txt" {
			return nil, nil, fmt.Errorf("unexpected call: %s %v", name, args)
		}
		return []byte(nativeText), nil, nil
	})

	server := setupTestServer(t, runner, allowedDir, 1)

	reqBody, _ := json.Marshal(ExtractRequest{
		PDFPath: pdfFile,
	})
	req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	server.Routes().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d (body: %s)", rec.Code, rec.Body.String())
	}

	var resp ExtractResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.Text != nativeText {
		t.Fatalf("expected text %q, got %q", nativeText, resp.Text)
	}
	if resp.OCRUsed {
		t.Fatal("expected ocr_used to be false")
	}
	if resp.Truncated {
		t.Fatal("expected truncated to be false")
	}
}

func TestExtract_OCRDisabledFallback_SuccessAndTruncation(t *testing.T) {
	allowedDir := t.TempDir()
	pdfFile := filepath.Join(allowedDir, "scanned.pdf")
	if err := os.WriteFile(pdfFile, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}

	runner := &mockRunner{}
	// 1. Native text extraction returns < 50 chars
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		return []byte("short"), nil, nil
	})
	// 2. mutool draw -F ocr.txt fails with "OCR Disabled in this build" in stderr
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		if name != "mutool" || args[2] != "ocr.txt" {
			return nil, nil, fmt.Errorf("expected mutool ocr.txt call, got: %s %v", name, args)
		}
		return nil, []byte("mutool: OCR Disabled in this build\n"), errors.New("exit status 1")
	})
	// 3. Fallback: mutool draw -F png renders pages
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		if name != "mutool" || args[2] != "png" {
			return nil, nil, fmt.Errorf("expected mutool png call, got: %s %v", name, args)
		}
		// Write 3 page PNG files to the template directory
		var outPattern string
		for i, arg := range args {
			if arg == "-o" && i+1 < len(args) {
				outPattern = args[i+1]
				break
			}
		}
		if outPattern == "" {
			return nil, nil, errors.New("missing -o pattern")
		}
		dir := filepath.Dir(outPattern)
		// Write an unrelated/non-matching png file to ensure it's ignored (finding 4)
		if err := os.WriteFile(filepath.Join(dir, "cover_thumbnail.png"), []byte("non-page png"), 0644); err != nil {
			return nil, nil, err
		}
		for p := 1; p <= 3; p++ {
			pageFile := filepath.Join(dir, fmt.Sprintf("page%d.png", p))
			if err := os.WriteFile(pageFile, []byte("fake png"), 0644); err != nil {
				return nil, nil, err
			}
		}
		return nil, nil, nil
	})
	// 4. Tesseract runs for page 1
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		if name != "tesseract" || !strings.Contains(args[0], "page1.png") {
			return nil, nil, fmt.Errorf("expected tesseract for page1, got: %s %v", name, args)
		}
		return []byte("Page 1 OCR text"), nil, nil
	})
	// 5. Tesseract runs for page 2
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		if name != "tesseract" || !strings.Contains(args[0], "page2.png") {
			return nil, nil, fmt.Errorf("expected tesseract for page2, got: %s %v", name, args)
		}
		return []byte("Page 2 OCR text"), nil, nil
	})

	server := setupTestServer(t, runner, allowedDir, 1)

	maxPages := 2
	reqBody, _ := json.Marshal(ExtractRequest{
		PDFPath:     pdfFile,
		MaxOCRPages: &maxPages,
	})
	req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	server.Routes().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d (body: %s)", rec.Code, rec.Body.String())
	}

	var resp ExtractResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	expectedText := "Page 1 OCR text\n\nPage 2 OCR text"
	if resp.Text != expectedText {
		t.Fatalf("expected text %q, got %q", expectedText, resp.Text)
	}
	if !resp.OCRUsed {
		t.Fatal("expected ocr_used to be true")
	}
	if !resp.Truncated {
		t.Fatal("expected truncated to be true since 3 pages > max 2")
	}
}

func TestExtract_OCREmptyText(t *testing.T) {
	allowedDir := t.TempDir()
	pdfFile := filepath.Join(allowedDir, "empty_scanned.pdf")
	if err := os.WriteFile(pdfFile, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}

	runner := &mockRunner{}
	// Native text is empty
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		return []byte(""), nil, nil
	})
	// mutool OCR disabled
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		return nil, []byte("OCR Disabled in this build\n"), errors.New("exit status 1")
	})
	// mutool PNG render creates 1 page
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		var outPattern string
		for i, arg := range args {
			if arg == "-o" && i+1 < len(args) {
				outPattern = args[i+1]
				break
			}
		}
		dir := filepath.Dir(outPattern)
		pageFile := filepath.Join(dir, "page1.png")
		return nil, nil, os.WriteFile(pageFile, []byte("fake png"), 0644)
	})
	// Tesseract returns empty whitespace text
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		return []byte("   \n\t  "), nil, nil
	})

	server := setupTestServer(t, runner, allowedDir, 1)

	reqBody, _ := json.Marshal(ExtractRequest{
		PDFPath: pdfFile,
	})
	req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	server.Routes().ServeHTTP(rec, req)

	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected status 422, got %d (body: %s)", rec.Code, rec.Body.String())
	}

	var errResp ErrorResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &errResp); err != nil {
		t.Fatalf("failed to decode error response: %v", err)
	}
	if errResp.Error == "" {
		t.Fatal("expected non-empty error in response")
	}
}

func TestExtract_DirectMutoolOCRSuccess(t *testing.T) {
	allowedDir := t.TempDir()
	pdfFile := filepath.Join(allowedDir, "bundled_ocr.pdf")
	if err := os.WriteFile(pdfFile, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}

	runner := &mockRunner{}
	// Native text is empty
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		return []byte(""), nil, nil
	})
	// mutool bundled OCR succeeds!
	ocrText := "Bundled mutool OCR successfully extracted this text from scanned bill."
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		return []byte(ocrText), nil, nil
	})

	server := setupTestServer(t, runner, allowedDir, 1)

	reqBody, _ := json.Marshal(ExtractRequest{
		PDFPath: pdfFile,
	})
	req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	server.Routes().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d (body: %s)", rec.Code, rec.Body.String())
	}

	var resp ExtractResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.Text != ocrText {
		t.Fatalf("expected text %q, got %q", ocrText, resp.Text)
	}
	if !resp.OCRUsed {
		t.Fatal("expected ocr_used to be true")
	}
	if resp.Truncated {
		t.Fatal("expected truncated to be false")
	}
}

func TestExtract_Concurrency(t *testing.T) {
	allowedDir := t.TempDir()
	pdfFile := filepath.Join(allowedDir, "concurrent.pdf")
	if err := os.WriteFile(pdfFile, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}

	blockReq1 := make(chan struct{})
	req1Started := make(chan struct{})

	runner := &mockRunner{}
	// First call blocks until blockReq1 is closed
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		close(req1Started)
		<-blockReq1
		return []byte("This is over fifty characters of native text for request 1 successfully returned."), nil, nil
	})

	cfg := Config{
		Port:           "8085",
		AllowedRoot:    allowedDir,
		Concurrency:    1,
		Timeout:        100 * time.Millisecond,
		MinNativeChars: 50,
		OCRDPI:         300,
		MaxOCRPages:    50,
	}
	server, err := NewServer(cfg, runner)
	if err != nil {
		t.Fatal(err)
	}

	var wg sync.WaitGroup
	wg.Add(1)

	var rec1 *httptest.ResponseRecorder
	go func() {
		defer wg.Done()
		reqBody, _ := json.Marshal(ExtractRequest{PDFPath: pdfFile})
		req1 := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
		req1.Header.Set("Content-Type", "application/json")
		rec1 = httptest.NewRecorder()
		server.Routes().ServeHTTP(rec1, req1)
	}()

	// Wait until req1 has acquired the slot and is inside the runner
	select {
	case <-req1Started:
	case <-time.After(1 * time.Second):
		t.Fatal("req1 did not start in time")
	}

	// Now send req2 with a client context that expires while waiting for the slot
	reqBody, _ := json.Marshal(ExtractRequest{PDFPath: pdfFile})
	ctx2, cancel2 := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel2()
	req2 := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody)).WithContext(ctx2)
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()

	server.Routes().ServeHTTP(rec2, req2)

	if rec2.Code != http.StatusGatewayTimeout {
		t.Fatalf("expected status 504 for timed-out queued request, got %d (body: %s)", rec2.Code, rec2.Body.String())
	}

	var errResp ErrorResponse
	if err := json.Unmarshal(rec2.Body.Bytes(), &errResp); err != nil {
		t.Fatalf("failed to decode error response: %v", err)
	}
	if !strings.Contains(errResp.Error, "client cancelled while waiting for extraction slot") {
		t.Fatalf("expected error containing 'client cancelled while waiting for extraction slot', got %q", errResp.Error)
	}

	// Unblock req1
	close(blockReq1)
	wg.Wait()

	if rec1.Code != http.StatusOK {
		t.Fatalf("expected status 200 for req1, got %d (body: %s)", rec1.Code, rec1.Body.String())
	}
}

func TestExtract_OCRDisabledMemoization(t *testing.T) {
	allowedDir := t.TempDir()
	pdfFile := filepath.Join(allowedDir, "scanned.pdf")
	if err := os.WriteFile(pdfFile, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}

	runner := &mockRunner{}
	// Request 1:
	// 1. Native text: short
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		return []byte("short"), nil, nil
	})
	// 2. mutool ocr.txt: OCR Disabled
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		return nil, []byte("mutool: OCR Disabled in this build\n"), errors.New("exit status 1")
	})
	// 3. mutool png render
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		var outPattern string
		for i, arg := range args {
			if arg == "-o" && i+1 < len(args) {
				outPattern = args[i+1]
				break
			}
		}
		dir := filepath.Dir(outPattern)
		pageFile := filepath.Join(dir, "page1.png")
		return nil, nil, os.WriteFile(pageFile, []byte("fake png"), 0644)
	})
	// 4. tesseract
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		return []byte("Page 1 OCR text"), nil, nil
	})

	// Request 2 (should skip mutool ocr.txt because mutoolOCRUnavailable is memoized):
	// 1. Native text: short
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		return []byte("short"), nil, nil
	})
	// 2. Directly mutool png render (mutool ocr.txt skipped!)
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		if name != "mutool" || args[2] != "png" {
			return nil, nil, fmt.Errorf("expected mutool png, got %s %v", name, args)
		}
		var outPattern string
		for i, arg := range args {
			if arg == "-o" && i+1 < len(args) {
				outPattern = args[i+1]
				break
			}
		}
		dir := filepath.Dir(outPattern)
		pageFile := filepath.Join(dir, "page1.png")
		return nil, nil, os.WriteFile(pageFile, []byte("fake png"), 0644)
	})
	// 3. tesseract
	runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
		return []byte("Page 1 memoized OCR text"), nil, nil
	})

	server := setupTestServer(t, runner, allowedDir, 1)

	// Execute request 1
	reqBody, _ := json.Marshal(ExtractRequest{PDFPath: pdfFile})
	req1 := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
	req1.Header.Set("Content-Type", "application/json")
	rec1 := httptest.NewRecorder()
	server.Routes().ServeHTTP(rec1, req1)

	if rec1.Code != http.StatusOK {
		t.Fatalf("expected status 200 on req1, got %d (body: %s)", rec1.Code, rec1.Body.String())
	}

	// Execute request 2
	req2 := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	server.Routes().ServeHTTP(rec2, req2)

	if rec2.Code != http.StatusOK {
		t.Fatalf("expected status 200 on req2, got %d (body: %s)", rec2.Code, rec2.Body.String())
	}

	// Verify that ocr.txt was only called ONCE across both requests
	runner.mu.Lock()
	ocrCallCount := 0
	for _, call := range runner.calls {
		if len(call) >= 4 && call[0] == "mutool" && call[3] == "ocr.txt" {
			ocrCallCount++
		}
	}
	runner.mu.Unlock()

	if ocrCallCount != 1 {
		t.Fatalf("expected mutool ocr.txt to be called exactly 1 time (memoized thereafter), but got %d", ocrCallCount)
	}
}

func TestExtract_ParameterValidation(t *testing.T) {
	allowedDir := t.TempDir()
	pdfFile := filepath.Join(allowedDir, "sample.pdf")
	if err := os.WriteFile(pdfFile, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}

	tests := []struct {
		name       string
		req        ExtractRequest
		expectCode int
	}{
		{
			name: "ocr_dpi too low",
			req: ExtractRequest{
				PDFPath: pdfFile,
				OCRDPI:  intPtr(40),
			},
			expectCode: http.StatusBadRequest,
		},
		{
			name: "ocr_dpi too high",
			req: ExtractRequest{
				PDFPath: pdfFile,
				OCRDPI:  intPtr(1500),
			},
			expectCode: http.StatusBadRequest,
		},
		{
			name: "max_ocr_pages too low",
			req: ExtractRequest{
				PDFPath:     pdfFile,
				MaxOCRPages: intPtr(0),
			},
			expectCode: http.StatusBadRequest,
		},
		{
			name: "max_ocr_pages too high",
			req: ExtractRequest{
				PDFPath:     pdfFile,
				MaxOCRPages: intPtr(501),
			},
			expectCode: http.StatusBadRequest,
		},
		{
			name: "min_native_chars negative",
			req: ExtractRequest{
				PDFPath:        pdfFile,
				MinNativeChars: intPtr(-1),
			},
			expectCode: http.StatusBadRequest,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			runner := &mockRunner{}
			server := setupTestServer(t, runner, allowedDir, 1)

			reqBody, _ := json.Marshal(tc.req)
			req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
			req.Header.Set("Content-Type", "application/json")
			rec := httptest.NewRecorder()

			server.Routes().ServeHTTP(rec, req)

			if rec.Code != tc.expectCode {
				t.Fatalf("expected status %d, got %d (body: %s)", tc.expectCode, rec.Code, rec.Body.String())
			}
		})
	}
}

func intPtr(i int) *int {
	return &i
}

func TestExtract_ContainerRootTranslation(t *testing.T) {
	allowedDir := t.TempDir()
	outsideDir := t.TempDir()

	legDir := filepath.Join(allowedDir, "legislation")
	if err := os.MkdirAll(legDir, 0755); err != nil {
		t.Fatal(err)
	}

	billPDF := filepath.Join(legDir, "bill.pdf")
	if err := os.WriteFile(billPDF, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}
	expectedResolvedPDF, err := filepath.EvalSymlinks(billPDF)
	if err != nil {
		t.Fatal(err)
	}

	outsidePDF := filepath.Join(outsideDir, "outside.pdf")
	if err := os.WriteFile(outsidePDF, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}

	escapeSymlink := filepath.Join(legDir, "escape.pdf")
	if err := os.Symlink(outsidePDF, escapeSymlink); err != nil {
		t.Fatal(err)
	}

	t.Run("translates container storage path to host allowed root", func(t *testing.T) {
		runner := &mockRunner{}
		nativeText := "Container path translated to host storage path and extracted over fifty characters."
		runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
			if name != "mutool" || len(args) != 4 || args[0] != "draw" || args[1] != "-F" || args[2] != "txt" {
				return nil, nil, fmt.Errorf("unexpected call: %s %v", name, args)
			}
			if args[3] != expectedResolvedPDF {
				return nil, nil, fmt.Errorf("expected resolved host path %q, got %q", expectedResolvedPDF, args[3])
			}
			return []byte(nativeText), nil, nil
		})

		server := setupTestServer(t, runner, allowedDir, 1)

		reqBody, _ := json.Marshal(ExtractRequest{
			PDFPath: "/rails/storage/legislation/bill.pdf",
		})
		req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()

		server.Routes().ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected status 200, got %d (body: %s)", rec.Code, rec.Body.String())
		}

		var resp ExtractResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to decode response: %v", err)
		}
		if resp.Text != nativeText {
			t.Fatalf("expected text %q, got %q", nativeText, resp.Text)
		}
	})

	t.Run("requesting container root directory itself fails with allowed root directory error", func(t *testing.T) {
		runner := &mockRunner{}
		server := setupTestServer(t, runner, allowedDir, 1)

		reqBody, _ := json.Marshal(ExtractRequest{
			PDFPath: "/rails/storage",
		})
		req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()

		server.Routes().ServeHTTP(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d (body: %s)", rec.Code, rec.Body.String())
		}

		var errResp ErrorResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &errResp); err != nil {
			t.Fatalf("failed to decode error response: %v", err)
		}
		if !strings.Contains(errResp.Error, "cannot be the allowed root directory itself") {
			t.Fatalf("expected error containing 'cannot be the allowed root directory itself', got %q", errResp.Error)
		}
	})

	t.Run("container path symlink escaping allowed root fails with outside allowed root", func(t *testing.T) {
		runner := &mockRunner{}
		server := setupTestServer(t, runner, allowedDir, 1)

		reqBody, _ := json.Marshal(ExtractRequest{
			PDFPath: "/rails/storage/legislation/escape.pdf",
		})
		req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()

		server.Routes().ServeHTTP(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d (body: %s)", rec.Code, rec.Body.String())
		}

		var errResp ErrorResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &errResp); err != nil {
			t.Fatalf("failed to decode error response: %v", err)
		}
		if !strings.Contains(errResp.Error, "outside allowed root") {
			t.Fatalf("expected error containing 'outside allowed root', got %q", errResp.Error)
		}
	})

	t.Run("container path traversal fails with outside allowed root", func(t *testing.T) {
		runner := &mockRunner{}
		server := setupTestServer(t, runner, allowedDir, 1)

		reqBody, _ := json.Marshal(ExtractRequest{
			PDFPath: "/rails/storage/../../etc/passwd.pdf",
		})
		req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()

		server.Routes().ServeHTTP(rec, req)

		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected status 400, got %d (body: %s)", rec.Code, rec.Body.String())
		}

		var errResp ErrorResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &errResp); err != nil {
			t.Fatalf("failed to decode error response: %v", err)
		}
		if !strings.Contains(errResp.Error, "outside allowed root") {
			t.Fatalf("expected error containing 'outside allowed root', got %q", errResp.Error)
		}
	})

	t.Run("does not rewrite path when already inside allowed root under container root", func(t *testing.T) {
		nestedContainerRoot := filepath.Join(t.TempDir(), "rails", "storage")
		nestedAllowedRoot := filepath.Join(nestedContainerRoot, "subroot")
		if err := os.MkdirAll(nestedAllowedRoot, 0755); err != nil {
			t.Fatal(err)
		}
		nestedPDF := filepath.Join(nestedAllowedRoot, "direct.pdf")
		if err := os.WriteFile(nestedPDF, []byte("%PDF-1.4 test"), 0644); err != nil {
			t.Fatal(err)
		}
		expectedNestedPDF, err := filepath.EvalSymlinks(nestedPDF)
		if err != nil {
			t.Fatal(err)
		}

		resolved, err := validatePDFPath(nestedPDF, nestedAllowedRoot, nestedContainerRoot)
		if err != nil {
			t.Fatalf("expected valid path when already inside allowedRoot, got error: %v", err)
		}
		if resolved != expectedNestedPDF {
			t.Fatalf("expected resolved path %q, got %q", expectedNestedPDF, resolved)
		}
	})
}

func TestLoadConfigFromEnv_ContainerRoot(t *testing.T) {
	t.Run("defaults ContainerRoot to /rails/storage when unset", func(t *testing.T) {
		t.Setenv("PDF_EXTRACTOR_CONTAINER_ROOT", "")
		cfg := loadConfigFromEnv()
		if cfg.ContainerRoot != "/rails/storage" {
			t.Fatalf("expected default ContainerRoot '/rails/storage', got %q", cfg.ContainerRoot)
		}
	})

	t.Run("overrides ContainerRoot when PDF_EXTRACTOR_CONTAINER_ROOT is set", func(t *testing.T) {
		t.Setenv("PDF_EXTRACTOR_CONTAINER_ROOT", "  /custom/container/root  ")
		cfg := loadConfigFromEnv()
		if cfg.ContainerRoot != "/custom/container/root" {
			t.Fatalf("expected overridden ContainerRoot '/custom/container/root', got %q", cfg.ContainerRoot)
		}
	})
}

func TestExtract_DisableOCR(t *testing.T) {
	allowedDir := t.TempDir()
	pdfFile := filepath.Join(allowedDir, "testimony.pdf")
	if err := os.WriteFile(pdfFile, []byte("%PDF-1.4 test"), 0644); err != nil {
		t.Fatal(err)
	}

	t.Run("returns 200 OK with empty text when mutool draw txt outputs empty string and disable_ocr is true", func(t *testing.T) {
		runner := &mockRunner{}
		runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
			if name != "mutool" || len(args) < 3 || args[0] != "draw" || args[1] != "-F" || args[2] != "txt" {
				return nil, nil, fmt.Errorf("unexpected call: %s %v", name, args)
			}
			return []byte(""), nil, nil
		})

		server := setupTestServer(t, runner, allowedDir, 1)

		reqBody, _ := json.Marshal(ExtractRequest{
			PDFPath:    pdfFile,
			DisableOCR: true,
		})
		req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()

		server.Routes().ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected status 200, got %d (body: %s)", rec.Code, rec.Body.String())
		}

		var resp ExtractResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
			t.Fatalf("failed to decode response: %v", err)
		}
		if resp.Text != "" {
			t.Fatalf("expected empty text, got %q", resp.Text)
		}
		if resp.OCRUsed {
			t.Fatal("expected ocr_used to be false")
		}
		if resp.Truncated {
			t.Fatal("expected truncated to be false")
		}

		runner.mu.Lock()
		callCount := len(runner.calls)
		runner.mu.Unlock()
		if callCount != 1 {
			t.Fatalf("expected only 1 command invocation (mutool draw -F txt), got %d", callCount)
		}
	})

	t.Run("returns 500 Internal Server Error when mutool draw txt fails and disable_ocr is true", func(t *testing.T) {
		runner := &mockRunner{}
		runner.addHandler(func(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
			return nil, []byte("cannot open document\n"), errors.New("exit status 1")
		})

		server := setupTestServer(t, runner, allowedDir, 1)

		reqBody, _ := json.Marshal(ExtractRequest{
			PDFPath:    pdfFile,
			DisableOCR: true,
		})
		req := httptest.NewRequest(http.MethodPost, "/extract", bytes.NewReader(reqBody))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()

		server.Routes().ServeHTTP(rec, req)

		if rec.Code != http.StatusInternalServerError {
			t.Fatalf("expected status 500, got %d (body: %s)", rec.Code, rec.Body.String())
		}

		var errResp ErrorResponse
		if err := json.Unmarshal(rec.Body.Bytes(), &errResp); err != nil {
			t.Fatalf("failed to decode error response: %v", err)
		}
		if !strings.Contains(errResp.Error, "mutool failed:") {
			t.Fatalf("expected error containing 'mutool failed:', got %q", errResp.Error)
		}

		runner.mu.Lock()
		callCount := len(runner.calls)
		runner.mu.Unlock()
		if callCount != 1 {
			t.Fatalf("expected only 1 command invocation (mutool draw -F txt), got %d", callCount)
		}
	})
}
