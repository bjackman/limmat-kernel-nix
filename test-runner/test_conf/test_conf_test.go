package test_conf

import (
	"os"
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestParse(t *testing.T) {
	testCases := []struct {
		name        string
		jsonContent string
		expected    map[string]Test
		expectError bool
	}{
		{
			name: "valid test",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["echo", "hello"]
					}
				}
			}`,
			expected: map[string]Test{
				"foo.bar": {
					IsTest:  true,
					Command: []string{"echo", "hello"},
				},
			},
		},
		{
			name: "no tests",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": false,
						"command": ["echo", "hello"]
					}
				}
			}`,
			expected: map[string]Test{},
		},
		{
			name: "invalid json",
			jsonContent: `{
				"foo": {
			`,
			expectError: true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			tmpfile, err := os.CreateTemp("", "test.json")
			if err != nil {
				t.Fatal(err)
			}
			defer os.Remove(tmpfile.Name())

			if _, err := tmpfile.Write([]byte(tc.jsonContent)); err != nil {
				t.Fatal(err)
			}
			if err := tmpfile.Close(); err != nil {
				t.Fatal(err)
			}

			tests, err := Parse(tmpfile.Name())

			if tc.expectError {
				if err == nil {
					t.Fatal("expected an error, got nil")
				}
				return
			}

			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if diff := cmp.Diff(tc.expected, tests); diff != "" {
				t.Errorf("Parse() mismatch (-want +got):\n%s", diff)
			}
		})
	}
}
