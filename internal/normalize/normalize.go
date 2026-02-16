package normalize

import (
	"bufio"
	"encoding/json"
	"io"
	"log"
	"os"
)

// MCP list fields that must be empty arrays per spec, never null.
var listFields = []string{
	"tools",
	"prompts",
	"resources",
	"resourceTemplates",
}

// ProcessStdout reads JSON-RPC messages (one per line) from r,
// normalizes null array fields to empty arrays, and writes to w.
func ProcessStdout(r io.Reader, w *os.File) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)

	for scanner.Scan() {
		line := scanner.Bytes()
		fixed := fixNullArrays(line)
		w.Write(fixed)
		w.Write([]byte("\n"))
	}
	if err := scanner.Err(); err != nil {
		log.Printf("normalize: scanner error: %v", err)
	}
}

// fixNullArrays replaces null values with empty arrays for known MCP list
// fields inside JSON-RPC result objects.
func fixNullArrays(data []byte) []byte {
	var msg map[string]json.RawMessage
	if err := json.Unmarshal(data, &msg); err != nil {
		return data
	}

	resultRaw, ok := msg["result"]
	if !ok {
		return data
	}

	var result map[string]json.RawMessage
	if err := json.Unmarshal(resultRaw, &result); err != nil {
		return data
	}

	modified := false
	for _, field := range listFields {
		raw, exists := result[field]
		if exists && string(raw) == "null" {
			result[field] = json.RawMessage("[]")
			modified = true
		}
	}

	if !modified {
		return data
	}

	fixedResult, err := json.Marshal(result)
	if err != nil {
		return data
	}
	msg["result"] = json.RawMessage(fixedResult)

	fixed, err := json.Marshal(msg)
	if err != nil {
		return data
	}
	return fixed
}
