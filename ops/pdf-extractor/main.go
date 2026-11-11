package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

const (
	defaultAllowedRoot    = "/rails/storage"
	defaultContainerRoot  = "/rails/storage"
	defaultPort           = "8085"
	defaultConcurrency    = 1
	defaultTimeout        = 300 * time.Second
	defaultMinNativeChars = 50
	defaultOCRDPI         = 300
	defaultMaxOCRPages    = 50
	minOCRDPI             = 50
	maxOCRDPI             = 1200
	minMaxOCRPages        = 1
	maxMaxOCRPages        = 500
	ocrDisabledSignature  = "OCR Disabled in this build"
)

// Config holds runtime configuration for the PDF extractor service.
type Config struct {
	Port           string
	AllowedRoot    string
	ContainerRoot  string
	Concurrency    int
	Timeout        time.Duration
	MinNativeChars int
	OCRDPI         int
	MaxOCRPages    int
}

// CommandRunner abstracts subprocess execution for testing.
type CommandRunner interface {
	Run(ctx context.Context, name string, args ...string) (stdout []byte, stderr []byte, err error)
}

// OSCommandRunner executes commands via os/exec.
type OSCommandRunner struct{}

func (r *OSCommandRunner) Run(ctx context.Context, name string, args ...string) ([]byte, []byte, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	return stdout.Bytes(), stderr.Bytes(), err
}

// ExtractRequest defines the expected JSON payload for POST /extract.
type ExtractRequest struct {
	PDFPath        string `json:"pdf_path"`
	MinNativeChars *int   `json:"min_native_chars,omitempty"`
	OCRDPI         *int   `json:"ocr_dpi,omitempty"`
	MaxOCRPages    *int   `json:"max_ocr_pages,omitempty"`
	DisableOCR     bool   `json:"disable_ocr,omitempty"`
}

// ExtractResponse represents the successful extraction JSON response.
type ExtractResponse struct {
	Text      string `json:"text"`
	OCRUsed   bool   `json:"ocr_used"`
	Truncated bool   `json:"truncated"`
}

// ErrorResponse represents an error JSON response.
type ErrorResponse struct {
	Error string `json:"error"`
}

// Server provides the HTTP handlers and concurrency control.
type Server struct {
	cfg                  Config
	runner               CommandRunner
	sem                  chan struct{}
	mutoolOCRUnavailable atomic.Bool
}

// NewServer initializes a new Server.
func NewServer(cfg Config, runner CommandRunner) (*Server, error) {
	if runner == nil {
		runner = &OSCommandRunner{}
	}
	concurrency := cfg.Concurrency
	if concurrency < 1 {
		concurrency = 1
	}
	return &Server{
		cfg:    cfg,
		runner: runner,
		sem:    make(chan struct{}, concurrency),
	}, nil
}

// Routes builds and returns the http.Handler for the service.
func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/up", s.handleUp)
	mux.HandleFunc("/extract", s.handleExtract)
	return mux
}

func (s *Server) handleUp(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func (s *Server) handleExtract(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	var req ExtractRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: fmt.Sprintf("invalid JSON payload: %v", err)})
		return
	}

	resolvedPath, err := validatePDFPath(req.PDFPath, s.cfg.AllowedRoot, s.cfg.ContainerRoot)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	minNativeChars := s.cfg.MinNativeChars
	if req.MinNativeChars != nil {
		if *req.MinNativeChars < 0 {
			writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: "min_native_chars cannot be negative"})
			return
		}
		minNativeChars = *req.MinNativeChars
	}

	ocrDPI := s.cfg.OCRDPI
	if req.OCRDPI != nil {
		if *req.OCRDPI < minOCRDPI || *req.OCRDPI > maxOCRDPI {
			writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: fmt.Sprintf("ocr_dpi must be between %d and %d", minOCRDPI, maxOCRDPI)})
			return
		}
		ocrDPI = *req.OCRDPI
	}

	maxOCRPages := s.cfg.MaxOCRPages
	if req.MaxOCRPages != nil {
		if *req.MaxOCRPages < minMaxOCRPages || *req.MaxOCRPages > maxMaxOCRPages {
			writeJSON(w, http.StatusBadRequest, ErrorResponse{Error: fmt.Sprintf("max_ocr_pages must be between %d and %d", minMaxOCRPages, maxMaxOCRPages)})
			return
		}
		maxOCRPages = *req.MaxOCRPages
	}

	// Acquire concurrency semaphore
	select {
	case s.sem <- struct{}{}:
		defer func() { <-s.sem }()
	case <-r.Context().Done():
		writeJSON(w, http.StatusGatewayTimeout, ErrorResponse{Error: "client cancelled while waiting for extraction slot"})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), s.cfg.Timeout)
	defer cancel()

	resp, status, err := s.extract(ctx, resolvedPath, minNativeChars, ocrDPI, maxOCRPages, req.DisableOCR)
	if err != nil {
		writeJSON(w, status, ErrorResponse{Error: err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

// @lat: [[pdf-extraction-mutool-ocr-fallback#The extraction rules]]
func (s *Server) extract(ctx context.Context, pdfPath string, minNativeChars, ocrDPI, maxOCRPages int, disableOCR bool) (*ExtractResponse, int, error) {
	// Step 1: mutool draw -F txt <pdfPath>
	stdout, stderr, err := s.runner.Run(ctx, "mutool", "draw", "-F", "txt", pdfPath)
	if disableOCR {
		if err != nil {
			return nil, http.StatusInternalServerError, fmt.Errorf("mutool failed: %s (err: %w)", strings.TrimSpace(string(stderr)), err)
		}
		return &ExtractResponse{
			Text:      string(stdout),
			OCRUsed:   false,
			Truncated: false,
		}, http.StatusOK, nil
	}
	if err == nil && len(strings.TrimSpace(string(stdout))) >= minNativeChars {
		return &ExtractResponse{
			Text:      string(stdout),
			OCRUsed:   false,
			Truncated: false,
		}, http.StatusOK, nil
	}

	// Step 2: Fall back to OCR.
	if s.mutoolOCRUnavailable.Load() {
		return s.extractViaTesseractFallback(ctx, pdfPath, ocrDPI, maxOCRPages)
	}

	ocrStdout, ocrStderr, ocrErr := s.runner.Run(ctx, "mutool", "draw", "-F", "ocr.txt", "-r", strconv.Itoa(ocrDPI), pdfPath)

	if strings.Contains(string(ocrStderr), ocrDisabledSignature) || strings.Contains(string(ocrStdout), ocrDisabledSignature) {
		s.mutoolOCRUnavailable.Store(true)
		return s.extractViaTesseractFallback(ctx, pdfPath, ocrDPI, maxOCRPages)
	}

	if ocrErr != nil {
		return nil, http.StatusInternalServerError, fmt.Errorf("mutool ocr failed: %s (err: %w)", strings.TrimSpace(string(ocrStderr)), ocrErr)
	}

	ocrText := string(ocrStdout)
	if strings.TrimSpace(ocrText) == "" {
		return nil, http.StatusUnprocessableEntity, errors.New("ocr produced no text")
	}

	return &ExtractResponse{
		Text:      ocrText,
		OCRUsed:   true,
		Truncated: false,
	}, http.StatusOK, nil
}

var pageNumberRegex = regexp.MustCompile(`^page(\d+)\.png$`)

func (s *Server) extractViaTesseractFallback(ctx context.Context, pdfPath string, ocrDPI, maxOCRPages int) (*ExtractResponse, int, error) {
	tmpDir, err := os.MkdirTemp("", "pdf-extractor-ocr-*")
	if err != nil {
		return nil, http.StatusInternalServerError, fmt.Errorf("failed to create temporary directory: %w", err)
	}
	defer os.RemoveAll(tmpDir)

	outPattern := filepath.Join(tmpDir, "page%d.png")
	_, pngStderr, pngErr := s.runner.Run(ctx, "mutool", "draw", "-F", "png", "-r", strconv.Itoa(ocrDPI), "-o", outPattern, pdfPath)
	if pngErr != nil {
		return nil, http.StatusInternalServerError, fmt.Errorf("mutool png render failed: %s (err: %w)", strings.TrimSpace(string(pngStderr)), pngErr)
	}

	entries, err := os.ReadDir(tmpDir)
	if err != nil {
		return nil, http.StatusInternalServerError, fmt.Errorf("failed to read temporary directory: %w", err)
	}

	type pageInfo struct {
		path string
		num  int
	}
	var pages []pageInfo

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if strings.HasSuffix(name, ".png") {
			matches := pageNumberRegex.FindStringSubmatch(name)
			if len(matches) <= 1 {
				continue
			}
			pageNum, _ := strconv.Atoi(matches[1])
			pages = append(pages, pageInfo{
				path: filepath.Join(tmpDir, name),
				num:  pageNum,
			})
		}
	}

	if len(pages) == 0 {
		return nil, http.StatusUnprocessableEntity, errors.New("mutool png render produced no pages")
	}

	sort.Slice(pages, func(i, j int) bool {
		return pages[i].num < pages[j].num
	})

	truncated := false
	pagesToProcess := pages
	if len(pages) > maxOCRPages {
		pagesToProcess = pages[:maxOCRPages]
		truncated = true
	}

	pageTexts := make([]string, 0, len(pagesToProcess))
	for _, page := range pagesToProcess {
		tessStdout, tessStderr, tessErr := s.runner.Run(ctx, "tesseract", page.path, "stdout", "-l", "eng")
		if tessErr != nil {
			return nil, http.StatusInternalServerError, fmt.Errorf("tesseract failed on page %d: %s (err: %w)", page.num, strings.TrimSpace(string(tessStderr)), tessErr)
		}
		pageTexts = append(pageTexts, string(tessStdout))
	}

	joined := strings.Join(pageTexts, "\n\n")
	if strings.TrimSpace(joined) == "" {
		return nil, http.StatusUnprocessableEntity, errors.New("ocr produced no text (empty output)")
	}

	return &ExtractResponse{
		Text:      joined,
		OCRUsed:   true,
		Truncated: truncated,
	}, http.StatusOK, nil
}

// @lat: [[pdf-extraction-mutool-ocr-fallback#Optional remote extraction service#Path validation and concurrency budgeting in the Go service]]
func validatePDFPath(pdfPath, allowedRoot, containerRoot string) (string, error) {
	trimmed := strings.TrimSpace(pdfPath)
	if trimmed == "" {
		return "", errors.New("pdf_path is required")
	}

	cleanRoot := filepath.Clean(allowedRoot)
	absRoot, err := filepath.Abs(cleanRoot)
	if err != nil {
		return "", fmt.Errorf("invalid allowed root: %w", err)
	}

	cleanPath := filepath.Clean(trimmed)
	absPath := cleanPath
	if !filepath.IsAbs(absPath) {
		absPath = filepath.Join(absRoot, absPath)
	}
	absPath = filepath.Clean(absPath)

	relToAllowed, relAllowedErr := filepath.Rel(absRoot, absPath)
	alreadyInAllowedRoot := relAllowedErr == nil && relToAllowed != ".." && !strings.HasPrefix(relToAllowed, ".."+string(filepath.Separator))

	trimmedContainerRoot := strings.TrimSpace(containerRoot)
	if !alreadyInAllowedRoot && trimmedContainerRoot != "" && filepath.IsAbs(cleanPath) {
		cleanContainerRoot := filepath.Clean(trimmedContainerRoot)
		if cleanPath == cleanContainerRoot {
			absPath = absRoot
		} else if relToContainer, relErr := filepath.Rel(cleanContainerRoot, cleanPath); relErr == nil && relToContainer != "." && relToContainer != ".." && !strings.HasPrefix(relToContainer, ".."+string(filepath.Separator)) {
			absPath = filepath.Clean(filepath.Join(absRoot, relToContainer))
		}
	}

	// Lexical boundary check
	rel, err := filepath.Rel(absRoot, absPath)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("pdf_path %q is outside allowed root %q", pdfPath, absRoot)
	}
	if rel == "." {
		return "", errors.New("pdf_path cannot be the allowed root directory itself")
	}

	// Symlink and file existence boundary check
	evalRoot, errRoot := filepath.EvalSymlinks(absRoot)
	if errRoot != nil {
		return "", fmt.Errorf("invalid allowed root: %w", errRoot)
	}

	evalPath, errPath := filepath.EvalSymlinks(absPath)
	if errPath != nil {
		return "", fmt.Errorf("pdf_path does not exist or cannot be resolved: %w", errPath)
	}

	evalRel, err := filepath.Rel(evalRoot, evalPath)
	if err != nil || evalRel == ".." || strings.HasPrefix(evalRel, ".."+string(filepath.Separator)) {
		return "", fmt.Errorf("resolved pdf_path %q is outside allowed root %q", evalPath, evalRoot)
	}
	if evalRel == "." {
		return "", errors.New("pdf_path cannot be the allowed root directory itself")
	}

	fi, err := os.Stat(evalPath)
	if err != nil {
		return "", fmt.Errorf("failed to stat pdf_path: %w", err)
	}
	if !fi.Mode().IsRegular() {
		return "", fmt.Errorf("pdf_path %q is not a regular file", pdfPath)
	}

	if !strings.EqualFold(filepath.Ext(evalPath), ".pdf") {
		return "", fmt.Errorf("pdf_path %q must have a .pdf extension", pdfPath)
	}

	return evalPath, nil
}

func writeJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}

func loadConfigFromEnv() Config {
	port := os.Getenv("PORT")
	if port == "" {
		port = os.Getenv("PDF_EXTRACTOR_PORT")
	}
	if port == "" {
		port = defaultPort
	}

	allowedRoot := os.Getenv("PDF_EXTRACTOR_ALLOWED_ROOT")
	if allowedRoot == "" {
		allowedRoot = defaultAllowedRoot
	}

	containerRoot := strings.TrimSpace(os.Getenv("PDF_EXTRACTOR_CONTAINER_ROOT"))
	if containerRoot == "" {
		containerRoot = defaultContainerRoot
	}

	concurrency := defaultConcurrency
	if cStr := os.Getenv("PDF_EXTRACTOR_CONCURRENCY"); cStr != "" {
		if c, err := strconv.Atoi(cStr); err == nil && c > 0 {
			concurrency = c
		}
	}

	timeout := defaultTimeout
	if tStr := os.Getenv("PDF_EXTRACTOR_TIMEOUT_SECONDS"); tStr != "" {
		if t, err := strconv.Atoi(tStr); err == nil && t > 0 {
			timeout = time.Duration(t) * time.Second
		}
	}

	return Config{
		Port:           port,
		AllowedRoot:    allowedRoot,
		ContainerRoot:  containerRoot,
		Concurrency:    concurrency,
		Timeout:        timeout,
		MinNativeChars: defaultMinNativeChars,
		OCRDPI:         defaultOCRDPI,
		MaxOCRPages:    defaultMaxOCRPages,
	}
}

func main() {
	cfg := loadConfigFromEnv()
	server, err := NewServer(cfg, &OSCommandRunner{})
	if err != nil {
		log.Fatalf("failed to initialize server: %v", err)
	}

	httpServer := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      server.Routes(),
		ReadTimeout:  cfg.Timeout + 10*time.Second,
		WriteTimeout: cfg.Timeout + 10*time.Second,
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("Starting pdf-extractor on :%s (allowed root: %s, concurrency: %d)", cfg.Port, cfg.AllowedRoot, cfg.Concurrency)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("HTTP server failed: %v", err)
		}
	}()

	<-stop
	log.Println("Shutting down pdf-extractor...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(ctx); err != nil {
		log.Printf("HTTP shutdown error: %v", err)
	}
}
