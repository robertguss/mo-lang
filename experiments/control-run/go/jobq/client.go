package main

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
)

const maxResponseBytes = 16 << 20

func newHTTPClient() *http.Client {
	return &http.Client{Timeout: clientTimeout}
}

func validMethod(m string) bool {
	if m == "" {
		return false
	}
	for i := 0; i < len(m); i++ {
		if m[i] < 'A' || m[i] > 'Z' {
			return false
		}
	}
	return true
}

// doRequest sends one request. A token of "-" sends no authorization header.
func doRequest(c *http.Client, addr, token, method, path, body string) (int, []byte, error) {
	var rdr io.Reader
	if body != "" {
		rdr = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, "http://"+addr+path, rdr)
	if err != nil {
		return 0, nil, err
	}
	if token != "-" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes))
	return resp.StatusCode, data, err
}

// printResponse writes the status on one line and the body after it.
func printResponse(w io.Writer, status int, body []byte) {
	fmt.Fprintf(w, "%d\n", status)
	if len(body) > 0 {
		_, _ = w.Write(body)
		if body[len(body)-1] != '\n' {
			fmt.Fprintln(w)
		}
	}
}

func cmdClient(args []string, stdout, stderr io.Writer) int {
	if len(args) != 5 && len(args) != 6 {
		return usageError(stderr, "client takes <host> <port> <token> <method> <path> [<json>]")
	}
	host, token, method, path := args[0], args[2], args[3], args[4]
	if _, ok := parsePort(args[1]); !ok {
		return usageError(stderr, "<port> is 1 to 65535")
	}
	if !validMethod(method) || !strings.HasPrefix(path, "/") {
		return usageError(stderr, "<method> is uppercase letters and <path> starts with /")
	}
	body := ""
	if len(args) == 6 {
		body = args[5]
	}
	status, data, err := doRequest(newHTTPClient(), net.JoinHostPort(host, args[1]), token, method, path, body)
	if err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		return 1
	}
	printResponse(stdout, status, data)
	return 0
}
