package nodeset

// Split divides nodes into at most n groups of roughly equal size (differ by at most 1).
// Compatible with existing usage: Split(nodes, width) returns [][]string.
func Split(nodes []string, n int) [][]string {
	if n <= 0 || len(nodes) == 0 {
		return nil
	}
	if n >= len(nodes) {
		out := make([][]string, len(nodes))
		for i, v := range nodes {
			out[i] = []string{v}
		}
		return out
	}
	size := len(nodes) / n
	rem := len(nodes) % n
	var out [][]string
	idx := 0
	for i := 0; i < n && idx < len(nodes); i++ {
		sz := size
		if i < rem {
			sz++
		}
		end := idx + sz
		if end > len(nodes) {
			end = len(nodes)
		}
		out = append(out, nodes[idx:end])
		idx = end
	}
	return out
}
