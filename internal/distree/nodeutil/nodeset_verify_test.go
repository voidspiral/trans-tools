package nodeutil

import (
	"testing"

	"github.com/iskylite/nodeset"
)

func TestNodesetLib_MixedWidthRanges(t *testing.T) {
	tests := []struct {
		expr      string
		wantCount int
		first     string
		last      string
	}{
		{"cn[1-3,100-199]", 103, "cn1", "cn199"},
		{"cn[32-33,35-39,44-47,96-97,99-109,111-115,118-125]", 37, "cn32", "cn125"},
		{"cn[1,3,5]", 3, "cn1", "cn5"},
	}
	for _, tt := range tests {
		nodes, err := nodeset.Expand(tt.expr)
		if err != nil {
			t.Fatalf("Expand(%q) error: %v", tt.expr, err)
		}
		if len(nodes) != tt.wantCount {
			t.Errorf("Expand(%q) count=%d, want %d", tt.expr, len(nodes), tt.wantCount)
		}
		if nodes[0] != tt.first {
			t.Errorf("Expand(%q) first=%q, want %q", tt.expr, nodes[0], tt.first)
		}
		if nodes[len(nodes)-1] != tt.last {
			t.Errorf("Expand(%q) last=%q, want %q", tt.expr, nodes[len(nodes)-1], tt.last)
		}

		// Verify round-trip merge doesn't add padding
		merged, err := nodeset.Merge(nodes...)
		if err != nil {
			t.Fatalf("Merge(%q expanded) error: %v", tt.expr, err)
		}
		reExpanded, err := nodeset.Expand(merged)
		if err != nil {
			t.Fatalf("Expand(merged %q) error: %v", merged, err)
		}
		if len(reExpanded) != tt.wantCount {
			t.Errorf("round-trip count=%d, want %d (merged=%q)", len(reExpanded), tt.wantCount, merged)
		}
		t.Logf("%s -> merged=%s (%d nodes)", tt.expr, merged, len(nodes))
	}
}

func TestNodesetLib_PaddedVsUnpadded(t *testing.T) {
	// Unpadded: cn[1-3] should NOT produce cn001
	nodes, _ := nodeset.Expand("cn[1-3]")
	for _, n := range nodes {
		if len(n) > 3 { // "cn1" = 3 chars
			t.Errorf("unexpected padding: %q", n)
		}
	}

	// Padded: cn[001-003] SHOULD produce cn001
	padded, _ := nodeset.Expand("cn[001-003]")
	for _, n := range padded {
		if n != "cn001" && n != "cn002" && n != "cn003" {
			t.Errorf("expected padded node, got %q", n)
		}
	}
}
