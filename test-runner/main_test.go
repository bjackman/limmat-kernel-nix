package main

import (
	"os"
	"os/exec"
	"testing"

	"github.com/google/go-cmp/cmp"
)

func TestMain(t *testing.T) {
	testCases := []struct {
		name             string
		jsonContent      string
		testIdentifiers  string
		expectedOutput   string
		expectedExitCode int
	}{
		{
			name: "valid tests",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["echo", "hello"]
					},
					"baz": {
						"__is_test": true,
						"command": ["echo", "world"]
					}
				}
			}`,
			testIdentifiers:  "foo.bar,foo.baz",
			expectedOutput:   "hello\nworld\n",
			expectedExitCode: 0,
		},
		{
			name: "test not found",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["echo", "hello"]
					}
				}
			}`,
			testIdentifiers:  "foo.baz",
			expectedOutput:   "Error: no tests match pattern: foo.baz\nexit status 127\n",
			expectedExitCode: 1,
		},
		{
			name: "test fails",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["sh", "-c", "exit 1"]
					}
				}
			}`,
			testIdentifiers:  "foo.bar",
			expectedOutput:   "exit status 1\n",
			expectedExitCode: 1,
		},
		{
			name: "test fails with debug output",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["sh", "-c", "exit 1"]
					}
				}
			}`,
			testIdentifiers:  "foo.bar",
			expectedOutput:   "exit status 1\n",
			expectedExitCode: 1,
		},
		{
			name: "glob pattern matches multiple tests",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["echo", "hello"]
					},
					"baz": {
						"__is_test": true,
						"command": ["echo", "world"]
					}
				}
			}`,
			testIdentifiers:  "foo.*",
			expectedOutput:   "hello\nworld\n",
			expectedExitCode: 0,
		},
		{
			name: "glob pattern matches single test",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["echo", "hello"]
					},
					"baz": {
						"__is_test": true,
						"command": ["echo", "world"]
					}
				}
			}`,
			testIdentifiers:  "foo.ba?",
			expectedOutput:   "hello\nworld\n",
			expectedExitCode: 0,
		},
		{
			name: "no tests match glob pattern",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["echo", "hello"]
					}
				}
			}`,
			testIdentifiers:  "nonexistent.*",
			expectedOutput:   "Error: no tests match pattern: nonexistent.*\nexit status 127\n",
			expectedExitCode: 1,
		},
		{
			name: "invalid glob pattern",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["echo", "hello"]
					}
				}
			}`,
			testIdentifiers:  "foo[",
			expectedOutput:   "Error: invalid glob pattern foo[: syntax error in pattern\nexit status 127\n",
			expectedExitCode: 1,
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

			cmd := exec.Command("go", "run", ".", "-test-config", tmpfile.Name(), "-test-identifiers", tc.testIdentifiers)
			output, err := cmd.CombinedOutput()

			if tc.expectedExitCode == 0 {
				if err != nil {
					t.Errorf("expected no error, got %v", err)
				}
			} else {
				if err == nil {
					t.Errorf("expected an error, got none")
				} else {
					if exitErr, ok := err.(*exec.ExitError); ok {
						if exitErr.ExitCode() != tc.expectedExitCode {
							t.Errorf("expected exit code %d, got %d", tc.expectedExitCode, exitErr.ExitCode())
						}
					} else {
						t.Errorf("unexpected error type: %v", err)
					}
				}
			}

			if diff := cmp.Diff(tc.expectedOutput, string(output)); diff != "" {
				t.Errorf("Output mismatch (-want +got):\n%s", diff)
			}
		})
	}
}
