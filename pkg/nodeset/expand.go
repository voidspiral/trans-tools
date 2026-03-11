package nodeset

// Expand parses the pattern (pdsh-style and extended , ! & ^) and returns sorted unique node names.
func Expand(pat string) ([]string, error) {
	return ParseExpand(pat)
}

// Fold parses the pattern and returns its compact range form (deduped and folded).
func Fold(pat string) (string, error) {
	nodes, err := ParseExpand(pat)
	if err != nil {
		return "", err
	}
	return foldSlice(nodes), nil
}

// Merge folds the given node names into a single compact range string (dedupes and sorts).
// Compatible with existing usage: Merge(nodes...) returns the same as Fold after expanding a list.
func Merge(nodes ...string) (string, error) {
	if len(nodes) == 0 {
		return "", nil
	}
	return foldSlice(nodes), nil
}
