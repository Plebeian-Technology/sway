package scrapers

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"time"
)

// Client is a generic HTTP client for scrapers, inspired by FaradayConnector.
type Client struct {
	BaseURL    string
	HTTPClient *http.Client
	AuthHeader string
	Headers    map[string]string
}

// NewClient creates a new scraper client.
func NewClient(baseURL string) *Client {
	return &Client{
		BaseURL: baseURL,
		HTTPClient: &http.Client{
			Timeout: 10 * time.Second,
		},
		Headers: make(map[string]string),
	}
}

// WithAuthHeader sets an Authorization header for the client.
func (c *Client) WithAuthHeader(token string) *Client {
	c.AuthHeader = token
	return c
}

// WithHeader sets a custom header for the client.
func (c *Client) WithHeader(key, value string) *Client {
	c.Headers[key] = value
	return c
}

// Get performs a GET request to the specified path.
func (c *Client) Get(path string) ([]byte, error) {
	req, err := http.NewRequest("GET", c.BaseURL+path, nil)
	if err != nil {
		return nil, err
	}

	return c.do(req)
}

// Post performs a POST request to the specified path.
// For simplicity, this example assumes a nil body, but it could be extended.
func (c *Client) Post(path string, body io.Reader) ([]byte, error) {
	req, err := http.NewRequest("POST", c.BaseURL+path, body)
	if err != nil {
		return nil, err
	}

	return c.do(req)
}

// do executes the HTTP request and handles the response.
func (c *Client) do(req *http.Request) ([]byte, error) {
	// Set default and custom headers
	if c.AuthHeader != "" {
		req.Header.Set("Authorization", c.AuthHeader)
	}
	for key, value := range c.Headers {
		req.Header.Set(key, value)
	}

	resp, err := c.HTTPClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("request failed with status %d: %s", resp.StatusCode, string(body))
	}

	return io.ReadAll(resp.Body)
}

// ParseJSON is a helper to unmarshal JSON response body into a struct.
func ParseJSON(data []byte, v interface{}) error {
	return json.Unmarshal(data, v)
}

// ParseXML is a helper to unmarshal XML response body into a struct.
func ParseXML(data []byte, v interface{}) error {
	return xml.Unmarshal(data, v)
}
