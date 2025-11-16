package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"test-runner/runner"
	"test-runner/test_conf"
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
			fmt.Println("usage: test-runner [--test-config <file>] [--skip-tag <tag>] [--bail-on-failure] <test-id-glob>...")
			fmt.Println("       test-runner parse-kselftest-list <file>")
			return nil
		}
	}
	var testConfigFile string
	var skipTagsFlag stringSliceFlag
	var includeBadFlag stringSliceFlag
	var bailOnFailure bool
	flag.StringVar(&testConfigFile, "test-config", "", "Path to a JSON file with test definitions")
	flag.Var(&skipTagsFlag, "skip-tag", "Skip tests with this tag (repeatable)")
	flag.Var(&includeBadFlag, "include-bad", "Include tests with this bad tag (repeatable)")
	flag.BoolVar(&bailOnFailure, "bail-on-failure", false, "Stop running tests after the first failure")
	flag.Parse()

	if testConfigFile == "" {
		return fmt.Errorf("--test-config flag is required")
	}

	testIdentifiers := flag.Args()
	if len(testIdentifiers) == 0 {
		return fmt.Errorf("at least one test identifier is required")
	}

	conf, err := test_conf.Parse(testConfigFile)
	if err != nil {
		return fmt.Errorf("parsing test config: %v", err)
	}

	skipTags := make(map[string]bool)
	for _, tag := range skipTagsFlag {
		skipTags[tag] = true
	}
	includeBad := make(map[string]bool)
	for _, tag := range includeBadFlag {
		includeBad[tag] = true
	}
	badTags := make(map[string]bool)
	for _, tag := range conf.BadTags {
		badTags[tag] = true
	}

	requestedTests := make(map[string]test_conf.Test)
	for _, pattern := range testIdentifiers {
		matched := false
		for testID, test := range conf.Tests {
			match, err := filepath.Match(pattern, testID)
			if err != nil {
				return fmt.Errorf("invalid glob pattern %s: %v", pattern, err)
			}
			if match {
				matched = true
				requestedTests[testID] = test
			}
		}
		if !matched {
			return fmt.Errorf("no tests match pattern: %s", pattern)
		}
	}

	runResults, testErr := runner.RunTests(&runner.RunOptions{
		RequestedTests: requestedTests,
		SkipTags:       skipTags,
		IncludeBad:     includeBad,
		BadTags:        badTags,
		BailOnFailure:  bailOnFailure,
	})

	fmt.Println("\n=== Test Results Summary ===")
	passedCount := 0
	failedCount := 0
	errorCount := 0
	droppedCount := 0
	skippedCount := 0
	for _, result := range runResults {
		fmt.Printf("%-60s %s\n", result.TestID, result.Result)

		switch result.Result {
		case runner.TestPassed:
			passedCount++
		case runner.TestFailed:
			failedCount++
		case runner.TestError:
			errorCount++
		case runner.TestDropped:
			droppedCount++
		case runner.TestSkipped:
			skippedCount++
		}
	}
	fmt.Printf("\nTotal: %d, Passed: %d, Failed: %d, Error: %d, Skipped: %d, Dropped: %d\n",
		len(runResults), passedCount, failedCount, errorCount, skippedCount, droppedCount)

	if testErr != nil {
		return testErr
	}
	if failedCount != 0 {
		return ErrTestFailed
	}
	if passedCount == 0 {
		return fmt.Errorf("didn't run any tests")
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
