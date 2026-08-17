//go:build darwin

package clip

import (
	"os"
	"testing"
)

// Run with an empty environment (env -i) to simulate a Finder/launchd launch.
func TestUTF8RoundTrip(t *testing.T) {
	if os.Getenv("CLIPPY_LOCALE_REPRO") == "" {
		t.Skip("set CLIPPY_LOCALE_REPRO=1 to run (clobbers the system clipboard)")
	}
	const text = "Golang.cz - Work Report - květen 2026"
	if err := WriteAll(text); err != nil {
		t.Fatal(err)
	}
	got, err := readAll()
	if err != nil {
		t.Fatal(err)
	}
	if got != text {
		t.Fatalf("round trip corrupted: %q", got)
	}
}
