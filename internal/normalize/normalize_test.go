package normalize

import (
	"bytes"
	"encoding/json"
	"testing"
)

func mustParseResult(t *testing.T, data []byte) map[string]interface{} {
	t.Helper()
	var msg map[string]interface{}
	if err := json.Unmarshal(data, &msg); err != nil {
		t.Fatalf("failed to parse JSON: %v", err)
	}
	result, ok := msg["result"].(map[string]interface{})
	if !ok {
		t.Fatalf("no result object in response")
	}
	return result
}

func TestFixNullArrays_ResourcesNull(t *testing.T) {
	input := `{"jsonrpc":"2.0","id":1,"result":{"resources":null}}`
	got := fixNullArrays([]byte(input))
	result := mustParseResult(t, got)

	resources, ok := result["resources"].([]interface{})
	if !ok {
		t.Fatalf("resources should be an array, got %T", result["resources"])
	}
	if len(resources) != 0 {
		t.Errorf("resources should be empty, got %v", resources)
	}
}

func TestFixNullArrays_ToolsNull(t *testing.T) {
	input := `{"jsonrpc":"2.0","id":2,"result":{"tools":null}}`
	got := fixNullArrays([]byte(input))
	result := mustParseResult(t, got)

	tools, ok := result["tools"].([]interface{})
	if !ok {
		t.Fatalf("tools should be an array, got %T", result["tools"])
	}
	if len(tools) != 0 {
		t.Errorf("tools should be empty, got %v", tools)
	}
}

func TestFixNullArrays_MultipleNullFields(t *testing.T) {
	input := `{"jsonrpc":"2.0","id":3,"result":{"resources":null,"prompts":null}}`
	got := fixNullArrays([]byte(input))
	result := mustParseResult(t, got)

	for _, field := range []string{"resources", "prompts"} {
		arr, ok := result[field].([]interface{})
		if !ok {
			t.Errorf("%s should be an array, got %T", field, result[field])
		}
		if len(arr) != 0 {
			t.Errorf("%s should be empty, got %v", field, arr)
		}
	}
}

func TestFixNullArrays_NoResult(t *testing.T) {
	input := `{"jsonrpc":"2.0","id":4,"method":"tools/list"}`
	got := string(fixNullArrays([]byte(input)))
	if got != input {
		t.Errorf("should pass through unchanged, got %s", got)
	}
}

func TestFixNullArrays_NonNullResources(t *testing.T) {
	input := `{"jsonrpc":"2.0","id":5,"result":{"resources":[{"name":"test"}]}}`
	got := string(fixNullArrays([]byte(input)))
	if got != input {
		t.Errorf("should pass through unchanged, got %s", got)
	}
}

func TestFixNullArrays_InvalidJSON(t *testing.T) {
	input := `not json at all`
	got := string(fixNullArrays([]byte(input)))
	if got != input {
		t.Errorf("should pass through unchanged, got %s", got)
	}
}

func TestFixNullArrays_ResourceTemplatesNull(t *testing.T) {
	input := `{"jsonrpc":"2.0","id":6,"result":{"resourceTemplates":null}}`
	got := fixNullArrays([]byte(input))
	result := mustParseResult(t, got)

	templates, ok := result["resourceTemplates"].([]interface{})
	if !ok {
		t.Fatalf("resourceTemplates should be an array, got %T", result["resourceTemplates"])
	}
	if len(templates) != 0 {
		t.Errorf("resourceTemplates should be empty, got %v", templates)
	}
}

func TestFixNullArrays_PreservesNonTargetFields(t *testing.T) {
	input := `{"jsonrpc":"2.0","id":7,"result":{"resources":null,"nextCursor":"abc"}}`
	got := fixNullArrays([]byte(input))
	result := mustParseResult(t, got)

	if result["nextCursor"] != "abc" {
		t.Errorf("nextCursor should be preserved, got %v", result["nextCursor"])
	}
	if !bytes.Contains(got, []byte(`"resources":[]`)) {
		t.Errorf("resources should be empty array in output: %s", got)
	}
}
