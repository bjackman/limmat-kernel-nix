package main

import (
	"bufio"
	"encoding/json"
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
	TestFailed TestResult = "FAIL ❌"
	TestPassed TestResult = "PASS ✔️"
	TestError  TestResult = "ERR  🔥"
)

var ErrTestFailed = fmt.Errorf("one or more tests failed")

// stringSliceFlag implements flag.Value for collecting multiple --skip-tag values
type stringSliceFlag []string

func (s *stringSliceFlag) String() string {
	return strings.Join(*s, ",")
}

func (s *stringSliceFlag) Set(value string) error {
	*s = append(*s, value)
	return nil
}

// shouldSkipTest checks if a test should be skipped based on its tags
func shouldSkipTest(test test_conf.Test, skipTags []string) bool {
	for _, skipTag := range skipTags {
		for _, testTag := range test.Tags {
			if testTag == skipTag {
				return true
			}
		}
	}
	return false
}

func parseKselftestList(filePath string) error {
	file, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("opening file: %w", err)
	}
	defer file.Close()

	// I'm guessing kselftests are always exactly 2-levels deep. Haven't checked lol
	tests := make(map[string]map[string]*test_conf.Test)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		suiteName, testName, ok := strings.Cut(line, ":")
		if !ok {
			return fmt.Errorf("can't parse suite:name line from %s: %q", filePath, line)
		}
		if _, ok := tests[suiteName]; !ok {
			tests[suiteName] = make(map[string]*test_conf.Test)
		}
		suite := tests[suiteName]
		if _, ok := suite[testName]; ok {
			return fmt.Errorf("duplicate test %s:%s (suite %q test %q)",
				suiteName, testName, suiteName, testName)
		}
		suite[testName] = &test_conf.Test{
			IsTest:  true,
			Command: []string{"run_kselftest.sh", "--error-on-fail", "-t", line},
		}
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("reading file: %w", err)
	}

	out, err := json.MarshalIndent(tests, "", "  ")
	if err != nil {
		return fmt.Errorf("marshaling to json: %w", err)
	}
	fmt.Println(string(out))
	return nil
}

func doMain() error {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "parse-kselftest-list":
			if len(os.Args) != 3 {
				return fmt.Errorf("usage: test-runner parse-kselftest-list <file>")
			}
			return parseKselftestList(os.Args[2])
		case "help", "-h", "--help":
			fmt.Println("usage: test-runner [--test-config <file>] [--skip-tag <tag>] <test-id-glob>...")
			fmt.Println("       test-runner parse-kselftest-list <file>")
			return nil
		}
	}
	var testConfigFile string
	var skipTags stringSliceFlag
	flag.StringVar(&testConfigFile, "test-config", "", "Path to a JSON file with test definitions")
	flag.Var(&skipTags, "skip-tag", "Skip tests with this tag (repeatable)")
	flag.Parse()

	if testConfigFile == "" {
		return fmt.Errorf("--test-config flag is required")
	}

	testIdentifiers := flag.Args()
	if len(testIdentifiers) == 0 {
		return fmt.Errorf("at least one test identifier is required")
	}

	tests, err := test_conf.Parse(testConfigFile)
	if err != nil {
		return fmt.Errorf("parsing test config: %v", err)
	}

	requestedTests := make(map[string]test_conf.Test)
	for _, pattern := range testIdentifiers {
		matched := false
		for testID, test := range tests {
			match, err := filepath.Match(pattern, testID)
			if err != nil {
				return fmt.Errorf("invalid glob pattern %s: %v", pattern, err)
			}
			if match {
				matched = true
				if !shouldSkipTest(test, skipTags) {
					requestedTests[testID] = test
				}
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
		} else {
			results[testID] = TestPassed
		}
	}

	fmt.Println("\n=== Test Results Summary ===")
	passedCount := 0
	failedCount := 0
	errorCount := 0
	for _, testID := range testIDs {
		result := results[testID]
		fmt.Printf("%-60s %s\n", testID, result)

		switch result {
		case TestPassed:
			passedCount++
		case TestFailed:
			failedCount++
		case TestError:
			errorCount++
		}
	}
	fmt.Printf("\nTotal: %d, Passed: %d, Failed: %d, Error: %d\n",
		len(testIDs), passedCount, failedCount, errorCount)

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
