package junit

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"test-runner/runner"
)

// TODO: rename
func TestGenerateJUnitReport(t *testing.T) {
	tmpDir := t.TempDir()
	reportPath := filepath.Join(tmpDir, "report.xml")

	results := []*runner.TestResult{
		{
			TestID:    "suite1.test1",
			Result:    runner.TestPassed,
			StartTime: time.Now(),
			EndTime:   time.Now().Add(1 * time.Second),
		},
		{
			TestID:    "suite1.test2",
			Result:    runner.TestFailed,
			StartTime: time.Now(),
			EndTime:   time.Now().Add(2 * time.Second),
			LogFile:   createTempLogFile(t, "failure log"),
			Err:       fmt.Errorf("exit status 1"),
		},
		{
			TestID:    "suite2.test1",
			Result:    runner.TestSkipped,
			StartTime: time.Now(),
			EndTime:   time.Now(),
		},
		{
			TestID:    "suite2.test2",
			Result:    runner.TestError,
			StartTime: time.Now(),
			EndTime:   time.Now().Add(3 * time.Second),
			LogFile:   createTempLogFile(t, "error log"),
			Err:       fmt.Errorf("some error"),
		},
	}

	err := GenerateReport(results, reportPath)
	if err != nil {
		t.Fatalf("GenerateJUnitReport() failed: %v", err)
	}

	reportBytes, err := os.ReadFile(reportPath)
	if err != nil {
		t.Fatalf("failed to read report file: %v", err)
	}
	report := string(reportBytes)

	// TODO: This is AI slop
	if !strings.Contains(report, `name="suite1"`) {
		t.Error("report does not contain suite1")
	}
	if !strings.Contains(report, `name="suite2"`) {
		t.Error("report does not contain suite2")
	}
	if !strings.Contains(report, `tests="2"`) {
		t.Error("report does not contain correct test count")
	}
	if !strings.Contains(report, `failures="1"`) {
		t.Error("report does not contain correct failure count")
	}
	if !strings.Contains(report, `errors="1"`) {
		t.Error("report does not contain correct error count")
	}
	if !strings.Contains(report, `skipped="1"`) {
		t.Error("report does not contain correct skipped count")
	}
	if !strings.Contains(report, `name="test1"`) {
		t.Error("report does not contain test1")
	}
	if !strings.Contains(report, `name="test2"`) {
		t.Error("report does not contain test2")
	}
	if !strings.Contains(report, "<failure") {
		t.Error("report does not contain failure tag")
	}
	if !strings.Contains(report, "<error") {
		t.Error("report does not contain error tag")
	}
	if !strings.Contains(report, "<skipped") {
		t.Error("report does not contain skipped tag")
	}
	if !strings.Contains(report, "failure log") {
		t.Error("report does not contain failure log content")
	}
	if !strings.Contains(report, "error log") {
		t.Error("report does not contain error log content")
	}
}

func createTempLogFile(t *testing.T, content string) string {
	t.Helper()
	tmpFile, err := os.CreateTemp(t.TempDir(), "log")
	if err != nil {
		t.Fatalf("failed to create temp log file: %v", err)
	}
	_, err = tmpFile.WriteString(content)
	if err != nil {
		t.Fatalf("failed to write to temp log file: %v", err)
	}
	tmpFile.Close()
	return tmpFile.Name()
}

func TestSplitTestID(t *testing.T) {
	testCases := []struct {
		name      string
		testID    string
		wantSuite string
		wantTest  string
	}{
		{
			name:      "simple",
			testID:    "suite.test",
			wantSuite: "suite",
			wantTest:  "test",
		},
		{
			name:      "multi-part suite",
			testID:    "suite.subsuite.test",
			wantSuite: "suite.subsuite",
			wantTest:  "test",
		},
		{
			name:      "no suite",
			testID:    "test",
			wantSuite: "test",
			wantTest:  "test",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			gotSuite, gotTest := splitTestID(tc.testID)
			if gotSuite != tc.wantSuite {
				t.Errorf("splitTestID() gotSuite = %v, want %v", gotSuite, tc.wantSuite)
			}
			if gotTest != tc.wantTest {
				t.Errorf("splitTestID() gotTest = %v, want %v", gotTest, tc.wantTest)
			}
		})
	}
}
