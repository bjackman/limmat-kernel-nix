package runner

import (
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"test-runner/test_conf"
)

func TestRunTests(t *testing.T) {
	tmpDir := t.TempDir()
	logDir := filepath.Join(tmpDir, "logs")

	tests := map[string]test_conf.Test{
		"suite.pass_test": {
			Command: []string{"bash", "-c", "exit 0"},
			Tags:    []string{"tag1"},
		},
		"suite.fail_test": {
			Command: []string{"bash", "-c", "exit 1"},
			Tags:    []string{"tag2"},
		},
		"suite.skip_test": {
			Command: []string{"bash", "-c", "exit 0"},
			Tags:    []string{"skip_me"},
		},
		"suite.empty_cmd_test": {
			Command: []string{},
			Tags:    []string{"tag4"},
		},
		"suite.error_test": {
			Command: []string{"aweoooooooga"},
			Tags:    []string{"tag3"},
		},
	}

	opts := &RunOptions{
		RequestedTests: tests,
		SkipTags:       map[string]bool{"skip_me": true},
		IncludeBad:     nil,
		BadTags:        nil,
		LogDir:         logDir,
		BailOnFailure:  false,
	}

	runResults, err := RunTests(opts)
	if err == nil {
		t.Fatalf("RunTests expected to return an error for empty command, got nil")
	}
	if !strings.Contains(err.Error(), "empty command") {
		t.Fatalf("RunTests returned wrong error for empty command: %v", err)
	}

	if len(runResults) != 5 {
		t.Fatalf("Expected 5 test results, got %d", len(runResults))
	}

	// Check results
	// TODO: This is fucking stupid, expectations should be encoded in the
	// testcase list and then checked using cmp.Diff. But I'm out of vibe-coding
	// credits on Gemini free lol.
	for _, res := range runResults {
		switch res.TestID {
		case "suite.pass_test":
			if res.Result != TestPassed {
				t.Errorf("suite.pass_test expected %s, got %s", TestPassed, res.Result)
			}
		case "suite.fail_test":
			if res.Result != TestFailed {
				t.Errorf("suite.fail_test expected %s, got %s", TestFailed, res.Result)
			}
		case "suite.error_test":
			if res.Result != TestError {
				t.Errorf("suite.error_test expected %s, got %s", TestError, res.Result)
			}
			if res.Err == nil {
				t.Errorf("suite.error_test expected an error, got nil")
			}
		case "suite.skip_test":
			if res.Result != TestSkipped {
				t.Errorf("suite.skip_test expected %s, got %s", TestSkipped, res.Result)
			}
			if res.LogFile != "" {
				t.Errorf("suite.skip_test expected no log file, got %s", res.LogFile)
			}
		case "suite.empty_cmd_test":
			if res.Result != TestError {
				t.Errorf("suite.empty_cmd_test expected %s, got %s", TestError, res.Result)
			}
			if res.Err == nil {
				t.Errorf("suite.empty_cmd_test expected an error, got nil")
			}
			if res.LogFile != "" {
				t.Errorf("suite.empty_cmd_test expected no log file, got %s", res.LogFile)
			}
		default:
			t.Errorf("Unexpected test ID: %s", res.TestID)
		}

		if res.Result != TestSkipped && res.Result != TestError && res.TestID != "suite.empty_cmd_test" {
			if res.EndTime.Sub(res.StartTime) <= 0 {
				t.Errorf("Test %s: Expected EndTime > StartTime, got %v", res.TestID, res.EndTime.Sub(res.StartTime))
			}
		}
	}
}

func TestRunTestsBailOnFailure(t *testing.T) {
	tmpDir := t.TempDir()
	logDir := filepath.Join(tmpDir, "logs")

	tests := map[string]test_conf.Test{
		"suite.a_first_pass": {
			Command: []string{"bash", "-c", "exit 0"},
		},
		"suite.b_failing": {
			Command: []string{"bash", "-c", "exit 1"},
		},
		"suite.c_second_pass": {
			Command: []string{"bash", "-c", "exit 0"},
		},
	}

	opts := &RunOptions{
		RequestedTests: tests,
		LogDir:         logDir,
		BailOnFailure:  true,
	}

	runResults, err := RunTests(opts)
	if err != nil {
		t.Fatalf("RunTests returned error: %v", err)
	}

	if len(runResults) != 3 {
		t.Fatalf("Expected 3 test results, got %d", len(runResults))
	}

	sort.Slice(runResults, func(i, j int) bool {
		return runResults[i].TestID < runResults[j].TestID
	})

	// Check results
	for _, res := range runResults {
		switch res.TestID {
		case "suite.a_first_pass":
			if res.Result != TestPassed {
				t.Errorf("suite.a_first_pass expected %s, got %s", TestPassed, res.Result)
			}
		case "suite.b_failing":
			if res.Result != TestFailed {
				t.Errorf("suite.b_failing expected %s, got %s", TestFailed, res.Result)
			}
		case "suite.c_second_pass":
			if res.Result != TestDropped {
				t.Errorf("suite.c_second_pass expected %s, got %s", TestDropped, res.Result)
			}
		default:
			t.Errorf("Unexpected test ID: %s", res.TestID)
		}
	}
}
