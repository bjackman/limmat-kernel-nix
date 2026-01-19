package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"test-runner/junit"
	"test-runner/runner"
	"test-runner/search"
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

// Global flag variables
var (
	testConfigFile string
	skipTagsFlag   stringSliceFlag
	includeBadFlag stringSliceFlag
	bailOnFailure  bool
	logDir         string
	junitXMLPath   string
)

func registerGlobalFlags(fs *flag.FlagSet) {
	fs.StringVar(&testConfigFile, "test-config", testConfigFile, "Path to a JSON file with test definitions")
	// For other flags, we don't strictly need to carry over the value as default if they are
	// just accumulators or booleans that default to empty/false, unless we want to allow
	// overriding them. But for simplicity and consistency, let's just register them.
	// Note: stringSliceFlag (Var) doesn't take a default value in the same way,
	// it accumulates. If we re-register the same variable, it will keep accumulating
	// if we parse more flags. This is desired.
	fs.Var(&skipTagsFlag, "skip-tag", "Skip tests with this tag (repeatable)")
	fs.Var(&includeBadFlag, "include-bad", "Include tests with this bad tag (repeatable)")
	fs.BoolVar(&bailOnFailure, "bail-on-failure", bailOnFailure, "Stop running tests after the first failure")
	fs.StringVar(&logDir, "log-dir", logDir, "Path to a directory to store test logs")
	fs.StringVar(&junitXMLPath, "junit-xml", junitXMLPath, "Path to write a JUnit XML report")
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
		// Hack: The test config is a flat array, with nesting denoted as
		// suite.test.subtest or whatever. But, when exporting XML we want to
		// actually expose the nesting structure. So '.' is actualylly a special
		// character. So, just munge it away if it appears in the kselftest test
		// name.
		// The proper approach here would actually just be to have the TestConf
		// have a proper recursive structure at runtime like the JSON has.
		testName = strings.Replace(testName, ".", "_", -1)
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
			Command: []string{"run_kselftest.sh", "-t", line},
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

func doRun(testIdentifiers []string) error {
	if testConfigFile == "" {
		return fmt.Errorf("--test-config flag is required")
	}

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
			errMsg := fmt.Sprintf("no tests match pattern: %s", pattern)
			var keys []string
			for k := range conf.Tests {
				keys = append(keys, k)
			}
			if bestMatch, ok := search.FindClosestTest(pattern, keys); ok {
				errMsg += fmt.Sprintf("\nDid you mean '%s'?", bestMatch)
			}
			return fmt.Errorf(errMsg)
		}
	}

	runResults, testErr := runner.RunTests(&runner.RunOptions{
		RequestedTests: requestedTests,
		SkipTags:       skipTags,
		IncludeBad:     includeBad,
		BadTags:        badTags,
		LogDir:         logDir,
		BailOnFailure:  bailOnFailure,
	})

	if junitXMLPath != "" {
		if err := junit.GenerateReport(runResults, junitXMLPath); err != nil {
			return fmt.Errorf("generating JUnit report: %w", err)
		}
	}

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

func doMain() error {
	registerGlobalFlags(flag.CommandLine)
	flag.Usage = func() {
		fmt.Println("usage: test-runner [--test-config <file>] [--skip-tag <tag>] [--bail-on-failure] [--log-dir <path>] [--junit-xml <path>] [run] <test-id-glob>...")
		fmt.Println("       test-runner parse-kselftest-list <file>")
		fmt.Println("       test-runner list --test-config <file>")
		flag.PrintDefaults()
	}
	flag.Parse()

	args := flag.Args()
	if len(args) == 0 {
		// No subcommand or test identifiers
		fmt.Println("usage: test-runner [--test-config <file>] [--skip-tag <tag>] [--bail-on-failure] [--log-dir <path>] [--junit-xml <path>] [run] <test-id-glob>...")
		fmt.Println("       test-runner parse-kselftest-list <file>")
		fmt.Println("       test-runner list --test-config <file>")
		return nil
	}

	subcmd := args[0]
	switch subcmd {
	case "parse-kselftest-list":
		// Expect exactly one more argument: file path
		if len(args) != 2 {
			return fmt.Errorf("usage: test-runner parse-kselftest-list <file>")
		}
		return parseKselftestList(args[1])
	case "list":
		listCmd := flag.NewFlagSet("list", flag.ExitOnError)
		registerGlobalFlags(listCmd)
		if err := listCmd.Parse(args[1:]); err != nil {
			return err
		}
		if testConfigFile == "" {
			return fmt.Errorf("--test-config flag is required")
		}
		conf, err := test_conf.Parse(testConfigFile)
		if err != nil {
			return fmt.Errorf("parsing test config: %v", err)
		}
		var keys []string
		for k := range conf.Tests {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			fmt.Println(k)
		}
		return nil
	case "run":
		runCmd := flag.NewFlagSet("run", flag.ExitOnError)
		registerGlobalFlags(runCmd)
		if err := runCmd.Parse(args[1:]); err != nil {
			return err
		}
		return doRun(runCmd.Args())
	case "help", "-h", "--help":
		fmt.Println("usage: test-runner [--test-config <file>] [--skip-tag <tag>] [--bail-on-failure] [--log-dir <path>] [--junit-xml <path>] [run] <test-id-glob>...")
		fmt.Println("       test-runner parse-kselftest-list <file>")
		fmt.Println("       test-runner list --test-config <file>")
		return nil
	default:
		// Implicit run command
		// All args are treated as test identifiers
		return doRun(args)
	}
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
