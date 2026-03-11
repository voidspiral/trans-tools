package nodeset

import "sort"

// NodeSet holds a set of node names (sorted, unique) and provides ClusterShell-style set operations.
type NodeSet struct {
	nodes []string
}

// NewNodeSet parses the pattern (pdsh-style and extended , ! & ^) and returns a NodeSet.
func NewNodeSet(pat string) (*NodeSet, error) {
	nodes, err := ParseExpand(pat)
	if err != nil {
		return nil, err
	}
	return &NodeSet{nodes: nodes}, nil
}

// mustNodeSet parses other (string or *NodeSet) into a slice of nodes for set ops.
func (ns *NodeSet) mustNodeSet(other interface{}) []string {
	if ns == nil {
		return nil
	}
	switch o := other.(type) {
	case *NodeSet:
		if o == nil {
			return nil
		}
		return o.nodes
	case string:
		nodes, _ := ParseExpand(o)
		return nodes
	default:
		return nil
	}
}

// setFromNodes builds a map for membership tests.
func setFromNodes(nodes []string) map[string]struct{} {
	m := make(map[string]struct{}, len(nodes))
	for _, n := range nodes {
		m[n] = struct{}{}
	}
	return m
}

// Union returns a new NodeSet with elements from both ns and other (other can be *NodeSet or pattern string).
func (ns *NodeSet) Union(other interface{}) (*NodeSet, error) {
	o := ns.mustNodeSet(other)
	if o == nil {
		return ns.copy(), nil
	}
	m := setFromNodes(ns.nodes)
	for _, n := range o {
		m[n] = struct{}{}
	}
	return &NodeSet{nodes: mapToSorted(m)}, nil
}

// Intersection returns a new NodeSet with elements common to ns and other.
func (ns *NodeSet) Intersection(other interface{}) (*NodeSet, error) {
	o := ns.mustNodeSet(other)
	if o == nil {
		return &NodeSet{}, nil
	}
	om := setFromNodes(o)
	var out []string
	for _, n := range ns.nodes {
		if _, ok := om[n]; ok {
			out = append(out, n)
		}
	}
	return &NodeSet{nodes: out}, nil
}

// Difference returns a new NodeSet with elements in ns but not in other.
func (ns *NodeSet) Difference(other interface{}) (*NodeSet, error) {
	o := ns.mustNodeSet(other)
	if o == nil {
		return ns.copy(), nil
	}
	om := setFromNodes(o)
	var out []string
	for _, n := range ns.nodes {
		if _, ok := om[n]; !ok {
			out = append(out, n)
		}
	}
	return &NodeSet{nodes: out}, nil
}

// SymmetricDifference returns a new NodeSet with elements in exactly one of ns and other.
func (ns *NodeSet) SymmetricDifference(other interface{}) (*NodeSet, error) {
	o := ns.mustNodeSet(other)
	if o == nil {
		return ns.copy(), nil
	}
	nm := setFromNodes(ns.nodes)
	om := setFromNodes(o)
	out := make(map[string]struct{})
	for n := range nm {
		if _, ok := om[n]; !ok {
			out[n] = struct{}{}
		}
	}
	for n := range om {
		if _, ok := nm[n]; !ok {
			out[n] = struct{}{}
		}
	}
	return &NodeSet{nodes: mapToSorted(out)}, nil
}

// Update adds all nodes from other into ns in place.
func (ns *NodeSet) Update(other interface{}) error {
	o := ns.mustNodeSet(other)
	if o == nil {
		return nil
	}
	m := setFromNodes(ns.nodes)
	for _, n := range o {
		m[n] = struct{}{}
	}
	ns.nodes = mapToSorted(m)
	return nil
}

// IntersectionUpdate keeps in ns only nodes that are also in other.
func (ns *NodeSet) IntersectionUpdate(other interface{}) error {
	o := ns.mustNodeSet(other)
	if o == nil {
		ns.nodes = nil
		return nil
	}
	om := setFromNodes(o)
	var out []string
	for _, n := range ns.nodes {
		if _, ok := om[n]; ok {
			out = append(out, n)
		}
	}
	ns.nodes = out
	return nil
}

// DifferenceUpdate removes from ns all nodes that are in other.
func (ns *NodeSet) DifferenceUpdate(other interface{}) error {
	o := ns.mustNodeSet(other)
	if o == nil {
		return nil
	}
	om := setFromNodes(o)
	var out []string
	for _, n := range ns.nodes {
		if _, ok := om[n]; !ok {
			out = append(out, n)
		}
	}
	ns.nodes = out
	return nil
}

// Len returns the number of nodes.
func (ns *NodeSet) Len() int {
	if ns == nil {
		return 0
	}
	return len(ns.nodes)
}

// Contains reports whether node is in the set.
func (ns *NodeSet) Contains(node string) bool {
	if ns == nil {
		return false
	}
	for _, n := range ns.nodes {
		if n == node {
			return true
		}
	}
	return false
}

// Equal reports whether ns and other have the same nodes.
func (ns *NodeSet) Equal(other *NodeSet) bool {
	if ns == nil && other == nil {
		return true
	}
	if ns == nil || other == nil || len(ns.nodes) != len(other.nodes) {
		return false
	}
	for i := range ns.nodes {
		if ns.nodes[i] != other.nodes[i] {
			return false
		}
	}
	return true
}

// String returns the folded range form of the node set.
func (ns *NodeSet) String() string {
	if ns == nil || len(ns.nodes) == 0 {
		return ""
	}
	return foldSlice(ns.nodes)
}

// Expand returns the slice of node names.
func (ns *NodeSet) Expand() []string {
	if ns == nil {
		return nil
	}
	out := make([]string, len(ns.nodes))
	copy(out, ns.nodes)
	return out
}

// Iterator returns an iterator over the nodes (same semantics as Yield).
func (ns *NodeSet) Iterator() *Iterator {
	if ns == nil {
		return &Iterator{}
	}
	return &Iterator{nodes: ns.nodes, idx: 0}
}

// Split returns up to n NodeSets of roughly equal size.
func (ns *NodeSet) Split(n int) []*NodeSet {
	if ns == nil {
		return nil
	}
	groups := Split(ns.nodes, n)
	out := make([]*NodeSet, len(groups))
	for i, g := range groups {
		out[i] = &NodeSet{nodes: g}
	}
	return out
}

func (ns *NodeSet) copy() *NodeSet {
	if ns == nil {
		return nil
	}
	return &NodeSet{nodes: append([]string(nil), ns.nodes...)}
}

func mapToSorted(m map[string]struct{}) []string {
	list := make([]string, 0, len(m))
	for n := range m {
		list = append(list, n)
	}
	sortNodes(list)
	return list
}

func sortNodes(list []string) {
	sort.Slice(list, func(i, j int) bool { return nodeLess(list[i], list[j]) })
}
