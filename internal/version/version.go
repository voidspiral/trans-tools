package version

import "fmt"

var (
	Version   = "0.1.0"
	BuildTime = "unknown"
	GitCommit = "unknown"
)

func String() string {
	return fmt.Sprintf("trans-tools %s (build: %s, commit: %s)", Version, BuildTime, GitCommit)
}
