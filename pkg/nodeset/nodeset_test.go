package nodeset

import (
	"reflect"
	"testing"
)

func TestExpand(t *testing.T) {
	tests := []struct {
		pat  string
		want []string
	}{
		{"localhost", []string{"localhost"}},
		{"cn[0-2]", []string{"cn0", "cn1", "cn2"}},
		{"cn[0-2,5]", []string{"cn0", "cn1", "cn2", "cn5"}},
		{"localhost,cn[0-2,5]", []string{"cn0", "cn1", "cn2", "cn5", "localhost"}},
		{"node[1-3]", []string{"node1", "node2", "node3"}},
		{"node[1-10/2]", []string{"node1", "node3", "node5", "node7", "node9"}},
		{"foo[1-5]", []string{"foo1", "foo2", "foo3", "foo4", "foo5"}},
	}
	for _, tt := range tests {
		got, err := Expand(tt.pat)
		if err != nil {
			t.Errorf("Expand(%q) err = %v", tt.pat, err)
			continue
		}
		if !reflect.DeepEqual(got, tt.want) {
			t.Errorf("Expand(%q) = %v, want %v", tt.pat, got, tt.want)
		}
	}
}

func TestExpandExtended(t *testing.T) {
	// union
	got, err := Expand("node[0-3],node[2-5]")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"node0", "node1", "node2", "node3", "node4", "node5"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Expand(union) = %v, want %v", got, want)
	}
	// difference
	got, err = Expand("node[0-10]!node[8-10]")
	if err != nil {
		t.Fatal(err)
	}
	want = []string{"node0", "node1", "node2", "node3", "node4", "node5", "node6", "node7"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Expand(diff) = %v, want %v", got, want)
	}
	// intersection
	got, err = Expand("node[0-10]&node[5-13]")
	if err != nil {
		t.Fatal(err)
	}
	want = []string{"node5", "node6", "node7", "node8", "node9", "node10"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Expand(intersect) = %v, want %v", got, want)
	}
}

func TestMerge(t *testing.T) {
	// from myclush/utils/expnodes_test.go
	got, err := Merge("cn0", "cn3", "localhost")
	if err != nil {
		t.Fatal(err)
	}
	// order may vary; should contain all three in folded form
	if got == "" {
		t.Error("Merge(cn0, cn3, localhost) returned empty")
	}
	nodes, _ := Expand(got)
	m := make(map[string]struct{})
	for _, n := range nodes {
		m[n] = struct{}{}
	}
	for _, need := range []string{"cn0", "cn3", "localhost"} {
		if _, ok := m[need]; !ok {
			t.Errorf("Merge result missing node %q, got %q", need, got)
		}
	}
}

func TestMergeFoldRoundtrip(t *testing.T) {
	pat := "localhost,cn[0-2,5]"
	nodes, err := Expand(pat)
	if err != nil {
		t.Fatal(err)
	}
	merged, err := Merge(nodes...)
	if err != nil {
		t.Fatal(err)
	}
	// Fold(merged) should equal merged; re-expand should match
	nodes2, err := Expand(merged)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(nodes, nodes2) {
		t.Errorf("Roundtrip: Expand(Merge(Expand(%q))) = %v, want %v", pat, nodes2, nodes)
	}
}

func TestSplit(t *testing.T) {
	nodes := []string{"n1", "n2", "n3", "n4", "n5"}
	got := Split(nodes, 3)
	if len(got) != 3 {
		t.Fatalf("Split(5 nodes, 3) len = %d, want 3", len(got))
	}
	// sizes should be 2, 2, 1 or similar
	total := 0
	for i, g := range got {
		total += len(g)
		if len(g) < 1 || len(g) > 2 {
			t.Errorf("Split group %d len = %d", i, len(g))
		}
	}
	if total != 5 {
		t.Errorf("Split total nodes = %d, want 5", total)
	}
}

func TestYield(t *testing.T) {
	iter, err := Yield("cn[0-2]")
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for iter.Next() {
		got = append(got, iter.Value())
	}
	want := []string{"cn0", "cn1", "cn2"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Yield(cn[0-2]) = %v, want %v", got, want)
	}
}

func TestNodeSet(t *testing.T) {
	ns, err := NewNodeSet("foo[1-5]")
	if err != nil {
		t.Fatal(err)
	}
	if ns.Len() != 5 {
		t.Errorf("Len = %d, want 5", ns.Len())
	}
	if !ns.Contains("foo3") {
		t.Error("Contains(foo3) = false")
	}
	if ns.Contains("foo0") {
		t.Error("Contains(foo0) = true")
	}
	s := ns.String()
	if s == "" {
		t.Error("String() empty")
	}
	exp := ns.Expand()
	if len(exp) != 5 {
		t.Errorf("Expand len = %d, want 5", len(exp))
	}
}

func TestNodeSetUnion(t *testing.T) {
	ns, _ := NewNodeSet("node[1-3]")
	other, _ := NewNodeSet("node[3-5]")
	u, err := ns.Union(other)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"node1", "node2", "node3", "node4", "node5"}
	if !reflect.DeepEqual(u.Expand(), want) {
		t.Errorf("Union = %v, want %v", u.Expand(), want)
	}
}

func TestNodeSetDifference(t *testing.T) {
	ns, _ := NewNodeSet("node[0-10]")
	other, _ := NewNodeSet("node[8-10]")
	d, err := ns.Difference(other)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"node0", "node1", "node2", "node3", "node4", "node5", "node6", "node7"}
	if !reflect.DeepEqual(d.Expand(), want) {
		t.Errorf("Difference = %v, want %v", d.Expand(), want)
	}
}

func TestNodeSetSplit(t *testing.T) {
	ns, _ := NewNodeSet("foo[1-5]")
	parts := ns.Split(3)
	if len(parts) != 3 {
		t.Fatalf("Split(3) len = %d, want 3", len(parts))
	}
	var total int
	for _, p := range parts {
		total += p.Len()
	}
	if total != 5 {
		t.Errorf("Split total = %d, want 5", total)
	}
}

func TestFold(t *testing.T) {
	nodes := []string{"cn0", "cn1", "cn2", "cn5", "localhost"}
	got := foldSlice(nodes)
	// Should be something like "cn[0-2,5],localhost" or "localhost,cn[0-2,5]"
	if got == "" {
		t.Error("foldSlice returned empty")
	}
	back, _ := Expand(got)
	if !reflect.DeepEqual(back, nodes) {
		t.Errorf("Expand(foldSlice(nodes)) = %v, want %v", back, nodes)
	}
}
