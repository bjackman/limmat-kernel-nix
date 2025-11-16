package main

import (
	"encoding/json"
	"log"
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/google/go-cmp/cmp"
)

var testBinaryPath = "./test-runner-test-binary"

func TestParseKselftestList(t *testing.T) {
	kselftestList := `kvm:guest_memfd_test
futex:functional`
	expectedJSON := `{
  "futex": {
    "functional": {
      "__is_test": true,
      "command": [
        "run_kselftest.sh",
        "--error-on-fail",
        "-t",
        "futex:functional"
      ]
    }
  },
  "kvm": {
    "guest_memfd_test": {
      "__is_test": true,
      "command": [
        "run_kselftest.sh",
        "--error-on-fail",
        "-t",
        "kvm:guest_memfd_test"
      ]
    }
  }
}`

	tmpfile, err := os.CreateTemp("", "kselftest-list.txt")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(tmpfile.Name())

	if _, err := tmpfile.Write([]byte(kselftestList)); err != nil {
		t.Fatal(err)
	}
	if err := tmpfile.Close(); err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command("go", "run", ".", "parse-kselftest-list", tmpfile.Name())
	output, err := cmd.CombinedOutput()

	if err != nil {
		t.Errorf("expected no error, got %v", err)
	}

	// Unmarshal both to avoid formatting issues
	var expected, actual interface{}
	if err := json.Unmarshal([]byte(expectedJSON), &expected); err != nil {
		t.Fatalf("failed to unmarshal expected JSON: %v", err)
	}
	if err := json.Unmarshal(output, &actual); err != nil {
		t.Fatalf("failed to unmarshal actual output: %v", err)
	}

	if diff := cmp.Diff(expected, actual); diff != "" {
		t.Errorf("Output mismatch (-want +got):\n%s", diff)
	}
}

func TestMainFunc(t *testing.T) {
	testCases := []struct {
		name             string
		jsonContent      string
		testIdentifiers  string
		skipTags         []string
		includeBad       []string
		bailOnFailure    bool
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
			testIdentifiers: "foo.bar foo.baz",
			expectedOutput: `hello
world

=== Test Results Summary ===
foo.bar                                                      PASS ✔️
foo.baz                                                      PASS ✔️

Total: 2, Passed: 2, Failed: 0, Error: 0, Skipped: 0, Dropped: 0
`,
			expectedExitCode: 0,
		}, {
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
			expectedOutput:   "Error: no tests match pattern: foo.baz\n",
			expectedExitCode: 127,
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
			testIdentifiers: "foo.bar",
			expectedOutput: `
=== Test Results Summary ===
foo.bar                                                      FAIL ❌

Total: 1, Passed: 0, Failed: 1, Error: 0, Skipped: 0, Dropped: 0
`,
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
			testIdentifiers: "foo.bar",
			expectedOutput: `
=== Test Results Summary ===
foo.bar                                                      FAIL ❌

Total: 1, Passed: 0, Failed: 1, Error: 0, Skipped: 0, Dropped: 0
`,
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
			testIdentifiers: "foo.*",
			expectedOutput: `hello
world

=== Test Results Summary ===
foo.bar                                                      PASS ✔️
foo.baz                                                      PASS ✔️

Total: 2, Passed: 2, Failed: 0, Error: 0, Skipped: 0, Dropped: 0
`,
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
			testIdentifiers: "foo.ba?",
			expectedOutput: `hello
world

=== Test Results Summary ===
foo.bar                                                      PASS ✔️
foo.baz                                                      PASS ✔️

Total: 2, Passed: 2, Failed: 0, Error: 0, Skipped: 0, Dropped: 0
`,
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
			expectedOutput:   "Error: no tests match pattern: nonexistent.*\n",
			expectedExitCode: 127,
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
			expectedOutput:   "Error: invalid glob pattern foo[: syntax error in pattern\n",
			expectedExitCode: 127,
		},
		{
			name: "skip single tag",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["echo", "hello"],
						"tags": ["slow"]
					},
					"baz": {
						"__is_test": true,
						"command": ["echo", "world"]
					}
				}
			}`,
			testIdentifiers: "foo.*",
			skipTags:        []string{"slow"},
			expectedOutput: `world

=== Test Results Summary ===
foo.bar                                                      SKIP 🫥
foo.baz                                                      PASS ✔️

Total: 2, Passed: 1, Failed: 0, Error: 0, Skipped: 1, Dropped: 0
`,
			expectedExitCode: 0,
		},
		{
			name: "skip multiple tags",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["echo", "hello"],
						"tags": ["slow"]
					},
					"baz": {
						"__is_test": true,
						"command": ["echo", "world"],
						"tags": ["flaky"]
					},
					"qux": {
						"__is_test": true,
						"command": ["echo", "test"]
					}
				}
			}`,
			testIdentifiers: "foo.*",
			skipTags:        []string{"slow", "flaky"},
			expectedOutput: `test

=== Test Results Summary ===
foo.bar                                                      SKIP 🫥
foo.baz                                                      SKIP 🫥
foo.qux                                                      PASS ✔️

Total: 3, Passed: 1, Failed: 0, Error: 0, Skipped: 2, Dropped: 0
`,
			expectedExitCode: 0,
		},
		{
			name: "bail on failure",
			jsonContent: `{
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["sh", "-c", "exit 1"]
					},
					"baz": {
						"__is_test": true,
						"command": ["echo", "world"]
					}
				}
			}`,
			testIdentifiers: "foo.*",
			bailOnFailure:   true,
			expectedOutput: `
=== Test Results Summary ===
foo.bar                                                      FAIL ❌
foo.baz                                                      DROP ⏸️

Total: 2, Passed: 0, Failed: 1, Error: 0, Skipped: 0, Dropped: 1
`,
			expectedExitCode: 1,
		},
		{
			name: "bad tags are skipped by default",
			jsonContent: `{
				"bad_tags": ["bad"],
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["echo", "hello"],
						"tags": ["bad"]
					},
					"baz": {
						"__is_test": true,
						"command": ["echo", "world"]
					}
				}
			}`,
			testIdentifiers: "foo.*",
			expectedOutput: `world

=== Test Results Summary ===
foo.bar                                                      SKIP 🫥
foo.baz                                                      PASS ✔️

Total: 2, Passed: 1, Failed: 0, Error: 0, Skipped: 1, Dropped: 0
`,
			expectedExitCode: 0,
		},
		{
			name: "include bad tag",
			jsonContent: `{
				"bad_tags": ["bad"],
				"foo": {
					"bar": {
						"__is_test": true,
						"command": ["echo", "hello"],
						"tags": ["bad"]
					},
					"baz": {
						"__is_test": true,
						"command": ["echo", "world"]
					}
				}
			}`,
			testIdentifiers: "foo.*",
			includeBad:      []string{"bad"},
			expectedOutput: `hello
world

=== Test Results Summary ===
foo.bar                                                      PASS ✔️
foo.baz                                                      PASS ✔️

Total: 2, Passed: 2, Failed: 0, Error: 0, Skipped: 0, Dropped: 0
`,
			expectedExitCode: 0,
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

			args := []string{"--test-config", tmpfile.Name()}
			if tc.bailOnFailure {
				args = append(args, "--bail-on-failure")
			}
			for _, tag := range tc.skipTags {
				args = append(args, "--skip-tag", tag)
			}
			for _, tag := range tc.includeBad {
				args = append(args, "--include-bad", tag)
			}
			args = append(args, strings.Fields(tc.testIdentifiers)...)
			cmd := exec.Command(testBinaryPath, args...)
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

func TestMain(m *testing.M) {
	log.Println("Building the test binary...")

	buildCmd := exec.Command("go", "build", "-o", testBinaryPath, ".")
	buildCmd.Stdout = os.Stdout
	buildCmd.Stderr = os.Stderr

	if err := buildCmd.Run(); err != nil {
		log.Fatalf("Failed to build the binary: %v", err)
	}
	defer func() {
		if err := os.Remove(testBinaryPath); err != nil {
			log.Printf("Warning: Failed to remove binary: %v", err)
		}
	}()

	os.Exit(m.Run())
}
