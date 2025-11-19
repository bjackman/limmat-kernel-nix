package runner

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"test-runner/test_conf"
)

type TestStatus string

var (
	TestFailed TestStatus = "FAIL ❌"
	TestPassed TestStatus = "PASS ✔️"
	TestError  TestStatus = "ERR  🔥"
	// Skipped due to tags.
	TestSkipped TestStatus = "SKIP 🫥"
	// Not run because we aborted.
	TestDropped TestStatus = "DROP ⏸️"
)

type TestResult struct {
	TestID    string
	Result    TestStatus
	StartTime time.Time
	EndTime   time.Time
	LogFile   string
	Err       error // For execution errors, not test failures
}

type RunOptions struct {
	RequestedTests map[string]test_conf.Test
	SkipTags       map[string]bool
	IncludeBad     map[string]bool
	BadTags        map[string]bool
	LogDir         string
	// Stop running tests and return as soon as one fails. Not this really
	// specifically refers to failure, this doesn't affect the behaviour for
	// errors when running tests.
	BailOnFailure bool
}

// RunTests runs the tests in the RequestedTests and returns TestResults. It
// returns the first error encountered while running tests, but continues
// running other tests afterwards. Is this a good design? Not sure.
func RunTests(opts *RunOptions) ([]*TestResult, error) {
	var runResults []*TestResult
	var testErr error

	if opts.LogDir != "" {
		if err := os.MkdirAll(opts.LogDir, 0755); err != nil {
			return nil, fmt.Errorf("creating log directory: %w", err)
		}
	}

	var testIDs []string
	for testID := range opts.RequestedTests {
		testIDs = append(testIDs, testID)
	}
	sort.Strings(testIDs)

	for i, testID := range testIDs {
		test := opts.RequestedTests[testID]
		startTime := time.Now()

		if len(test.Command) == 0 {
			runResults = append(runResults, &TestResult{
				TestID:    testID,
				Result:    TestError,
				StartTime: startTime,
				EndTime:   time.Now(),
				Err:       fmt.Errorf("empty command"),
			})
			fmt.Printf("Error running %s: empty command\n", testID)
			if testErr == nil {
				testErr = fmt.Errorf("error running %s: empty command", testID)
			}
			continue
		}
		if shouldSkipTest(test, opts.SkipTags, opts.IncludeBad, opts.BadTags) {
			runResults = append(runResults, &TestResult{
				TestID:    testID,
				Result:    TestSkipped,
				StartTime: startTime,
				EndTime:   time.Now(),
			})
			continue
		}

		var logFile string
		var logWriter io.Writer
		if opts.LogDir != "" {
			logPath := filepath.Join(opts.LogDir, strings.ReplaceAll(testID, ".", "/")+".log")
			if err := os.MkdirAll(filepath.Dir(logPath), 0755); err != nil {
				return nil, fmt.Errorf("creating log directory for test %s: %w", testID, err)
			}
			f, err := os.Create(logPath)
			if err != nil {
				return nil, fmt.Errorf("creating log file for test %s: %w", testID, err)
			}
			defer f.Close()
			logFile = logPath
			logWriter = io.MultiWriter(f, os.Stdout)
		} else {
			logWriter = os.Stdout
		}

		cmd := exec.Command(test.Command[0], test.Command[1:]...)
		cmd.Stdout = logWriter
		cmd.Stderr = logWriter

		err := cmd.Run()
		endTime := time.Now()

		result := &TestResult{
			TestID:    testID,
			StartTime: startTime,
			EndTime:   endTime,
			LogFile:   logFile,
			Err:       err,
		}

		if err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				if exitErr.ExitCode() == 127 {
					result.Result = TestError
				} else {
					result.Result = TestFailed
				}
				if opts.BailOnFailure {
					runResults = append(runResults, result)
					for j := i + 1; j < len(testIDs); j++ {
						runResults = append(runResults, &TestResult{
							TestID:    testIDs[j],
							Result:    TestDropped,
							StartTime: endTime,
							EndTime:   endTime,
						})
					}
					return runResults, nil
				}
			} else {
				result.Result = TestError
				fmt.Printf("Error running %s: %v\n", testID, err)
				if testErr == nil {
					testErr = fmt.Errorf("error running %s: %v", testID, err)
				}
			}
		} else {
			result.Result = TestPassed
		}
		runResults = append(runResults, result)
	}

	return runResults, testErr
}

// shouldSkipTest checks if a test should be skipped based on its tags
func shouldSkipTest(test test_conf.Test, skipTags, includeBad, badTags map[string]bool) bool {
	isBad := false
	for _, testTag := range test.Tags {
		if badTags[testTag] {
			isBad = true
			break
		}
	}

	if isBad {
		if len(includeBad) == 0 {
			return true
		}
		for _, testTag := range test.Tags {
			if includeBad[testTag] {
				return false
			}
		}
		return true
	}

	for _, testTag := range test.Tags {
		if skipTags[testTag] {
			return true
		}
	}
	return false
}
