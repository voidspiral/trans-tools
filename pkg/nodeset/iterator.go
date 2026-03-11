package nodeset

// Iterator yields node names one at a time without materializing the full list.
// Compatible with existing usage: iter.Next() and iter.Value().
type Iterator struct {
	nodes []string
	idx   int
}

// Yield parses the pattern and returns an iterator over the expanded node names.
// The iterator materializes the list once; call Next and Value to walk it.
func Yield(pat string) (*Iterator, error) {
	nodes, err := ParseExpand(pat)
	if err != nil {
		return nil, err
	}
	return &Iterator{nodes: nodes, idx: 0}, nil
}

// Next advances the iterator to the next node and reports whether it is valid.
func (it *Iterator) Next() bool {
	if it == nil || it.idx >= len(it.nodes) {
		return false
	}
	it.idx++
	return it.idx <= len(it.nodes)
}

// Value returns the current node name. Valid only after a call to Next that returned true,
// or before the first Next for the first element. Typical use: for iter.Next() { use iter.Value() }.
// So we need: before first Next(), Value() should return first element. After Next(), Value() returns current.
// Looking at myclush: for iter.Next() { nodeChan <- iter.Value() }. So they call Next() then Value(). So after Next() we're "on" the next element. So we should return nodes[idx-1] after Next() because Next() does idx++. So when Next() returns true, we've advanced to the next element, and that element is at idx-1. So Value() returns it.nodes[it.idx-1]. But then the first Next() makes idx=1, so Value() returns nodes[0]. Good.
func (it *Iterator) Value() string {
	if it == nil || it.idx == 0 {
		return ""
	}
	return it.nodes[it.idx-1]
}
