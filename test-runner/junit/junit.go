package junit

import (
	"encoding/xml"
	"fmt"
	"os"
	"strings"
	"time"

	"test-runner/runner"
)

// TestSuites is the top-level element of the JUnit XML report.
type TestSuites struct {
	XMLName xml.Name    `xml:"testsuites"`
	Suites  []TestSuite `xml:"testsuite"`
}

// TestSuite represents a single test suite.
type TestSuite struct {
	XMLName   xml.Name   `xml:"testsuite"`
	Name      string     `xml:"name,attr"`
	Tests     int        `xml:"tests,attr"`
	Failures  int        `xml:"failures,attr"`
	Errors    int        `xml:"errors,attr"`
	Skipped   int        `xml:"skipped,attr"`
	Time      string     `xml:"time,attr"`
	TestCases []TestCase `xml:"testcase"`
}

// TestCase represents a single test case.
type TestCase struct {
	XMLName   xml.Name `xml:"testcase"`
	Name      string   `xml:"name,attr"`
	ClassName string   `xml:"classname,attr"`
	Time      string   `xml:"time,attr"`
	Failure   *Failure `xml:"failure,omitempty"`
	Skipped   *Skipped `xml:"skipped,omitempty"`
	Error     *Error   `xml:"error,omitempty"`
}

// Failure represents a test failure.
type Failure struct {
	XMLName xml.Name `xml:"failure"`
	Message string   `xml:"message,attr"`
	Content string   `xml:",cdata"`
}

// Skipped represents a skipped test.
type Skipped struct {
	XMLName xml.Name `xml:"skipped"`
	Message string   `xml:"message,attr"`
}

// Error represents an error during a test.
type Error struct {
	XMLName xml.Name `xml:"error"`
	Message string   `xml:"message,attr"`
	Content string   `xml:",cdata"`
}

func GenerateReport(results []*runner.TestResult, path string) error {
	suites := make(map[string]*TestSuite)
	for _, result := range results {
		suiteName, testName := splitTestID(result.TestID)
		if _, ok := suites[suiteName]; !ok {
			suites[suiteName] = &TestSuite{
				Name:      suiteName,
				TestCases: []TestCase{},
			}
		}

		suite := suites[suiteName]
		suite.Tests++

		duration := result.EndTime.Sub(result.StartTime)
		testCase := TestCase{
			Name:      testName,
			ClassName: suiteName,
			Time:      fmt.Sprintf("%.3f", duration.Seconds()),
		}

		switch result.Result {
		case runner.TestFailed:
			suite.Failures++
			logContent, err := getLogContent(result.LogFile)
			if err != nil {
				return fmt.Errorf("reading log file for failed test %s: %w", result.TestID, err)
			}
			testCase.Failure = &Failure{
				Message: "Test failed",
				Content: logContent,
			}
		case runner.TestError:
			suite.Errors++
			logContent, err := getLogContent(result.LogFile)
			if err != nil {
				return fmt.Errorf("reading log file for errored test %s: %w", result.TestID, err)
			}
			testCase.Error = &Error{
				Message: fmt.Sprintf("Test execution failed: %v", result.Err),
				Content: logContent,
			}
		case runner.TestSkipped:
			suite.Skipped++
			testCase.Skipped = &Skipped{Message: "Test skipped"}
		case runner.TestDropped:
			suite.Skipped++
			testCase.Skipped = &Skipped{Message: "Test dropped"}
		}
		suite.TestCases = append(suite.TestCases, testCase)
	}

	var testSuites []TestSuite
	for _, suite := range suites {
		var suiteDuration time.Duration
		for _, tc := range suite.TestCases {
			parsedTime, _ := time.ParseDuration(tc.Time + "s")
			suiteDuration += parsedTime
		}
		suite.Time = fmt.Sprintf("%.3f", suiteDuration.Seconds())
		testSuites = append(testSuites, *suite)
	}

	report := TestSuites{
		Suites: testSuites,
	}

	file, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("creating JUnit XML file: %w", err)
	}
	defer file.Close()

	_, err = file.WriteString(xml.Header)
	if err != nil {
		return fmt.Errorf("writing XML header: %w", err)
	}

	encoder := xml.NewEncoder(file)
	encoder.Indent("", "  ")
	if err := encoder.Encode(report); err != nil {
		return fmt.Errorf("encoding JUnit XML: %w", err)
	}

	return nil
}

func splitTestID(testID string) (string, string) {
	parts := strings.Split(testID, ".")
	if len(parts) > 1 {
		return strings.Join(parts[:len(parts)-1], "."), parts[len(parts)-1]
	}
	return testID, testID
}

func getLogContent(logFile string) (string, error) {
	if logFile == "" {
		return "", nil
	}
	content, err := os.ReadFile(logFile)
	if err != nil {
		return "", err
	}
	return string(content), nil
}
