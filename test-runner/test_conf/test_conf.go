package test_conf

import (
	"encoding/json"
	"fmt"
	"os"
)

type Test struct {
	IsTest  bool     `json:"__is_test"`
	Command []string `json:"command"`
	Tags    []string `json:"tags,omitempty"`
}

func Parse(testConfigFile string) (map[string]Test, error) {
	jsonBytes, err := os.ReadFile(testConfigFile)
	if err != nil {
		return nil, fmt.Errorf("error reading JSON file: %w", err)
	}

	var data map[string]interface{}
	err = json.Unmarshal(jsonBytes, &data)
	if err != nil {
		return nil, fmt.Errorf("error unmarshaling JSON: %w", err)
	}

	tests := make(map[string]Test)
	flatten("", data, tests, []string{})

	return tests, nil
}

// Er, this was vibe coded and it's fucking garbage, sorry.
func flatten(prefix string, node interface{}, tests map[string]Test, tags []string) {
	nodeAsMap, ok := node.(map[string]interface{})
	if !ok {
		return
	}

	// Re-marshal the child map to unmarshal it into the TestNode struct
	childBytes, err := json.Marshal(nodeAsMap)
	if err != nil {
		return
	}
	var test Test
	if err := json.Unmarshal(childBytes, &test); err == nil {
		if test.IsTest {
			if prefix != "" {
				test.Tags = append(test.Tags, tags...)
				tests[prefix] = test
			}
		}
	}

	currentTags := tags
	if test.Tags != nil {
		currentTags = append(currentTags, test.Tags...)
	}

	for key, childNode := range nodeAsMap {
		newPrefix := key
		if prefix != "" {
			newPrefix = prefix + "." + key
		}
		flatten(newPrefix, childNode, tests, currentTags)
	}
}
