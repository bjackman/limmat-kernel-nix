package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"test-runner/test_conf"
)

type TestResult string

var (
	TestFailed TestResult = "FAIL"
	TestPassed TestResult = "PASS"
	TestError  TestResult = "ERR"
)

var ErrTestFailed = fmt.Errorf("one or more tests failed")

func doMain() error {
	var testConfigFile string
	var testIdentifiers string
	flag.StringVar(&testConfigFile, "test-config", "", "Path to a JSON file with test definitions")
	flag.StringVar(&testIdentifiers, "test-identifiers", "", "Comma-separated list of test identifiers")
	flag.Parse()

	if testConfigFile == "" {
		return fmt.Errorf("--test-config flag is required")
	}

	if testIdentifiers == "" {
		return fmt.Errorf("--test-identifiers flag is required")
	}

	tests, err := test_conf.Parse(testConfigFile)
	if err != nil {
		return fmt.Errorf("parsing test config: %v", err)
	}

	requestedTests := make(map[string]test_conf.Test)
	for _, pattern := range strings.Split(testIdentifiers, ",") {
		matched := false
		for testID, test := range tests {
			match, err := filepath.Match(pattern, testID)
			if err != nil {
				return fmt.Errorf("invalid glob pattern %s: %v", pattern, err)
			}
			if match {
				requestedTests[testID] = test
				matched = true
			}
		}
		if !matched {
			return fmt.Errorf("no tests match pattern: %s", pattern)
		}
	}

	results := make(map[string]TestResult)
	failures := false
	var testErr error
	
	// Sort test IDs for deterministic execution order
	var testIDs []string
	for testID := range requestedTests {
		testIDs = append(testIDs, testID)
	}
	sort.Strings(testIDs)
	
	for _, testID := range testIDs {
		test := requestedTests[testID]
		if len(test.Command) == 0 {
			results[testID] = TestError
			fmt.Printf("Error running %s: empty command\n", testID)
			if testErr == nil {
				testErr = fmt.Errorf("error running %s: empty command", testID)
			}
			continue
		}
		cmd := exec.Command(test.Command[0], test.Command[1:]...)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			if _, ok := err.(*exec.ExitError); ok {
				results[testID] = TestFailed
				failures = true
			} else {
				results[testID] = TestError
				// Save first error, continue other tests
				fmt.Printf("Error running %s: %v\n", testID, err)
				if testErr == nil {
					testErr = fmt.Errorf("error running %s: %v", testID, err)
				}
			}
		}
	}

	if testErr != nil {
		return testErr
	}
	if failures {
		return ErrTestFailed
	}
	return nil
}

func main() {
	err := doMain()
	if errors.Is(err, ErrTestFailed) {
		os.Exit(1)
	}
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(127)
	}
}
