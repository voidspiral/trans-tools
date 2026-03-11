package nodeset

import (
	"sort"
	"strconv"
	"strings"
)

// foldSlice turns a sorted list of node names into a compact range string (pdsh-style).
// E.g. ["node1","node2","node3","node5"] -> "node[1-3,5]".
// Nodes are deduplicated and sorted before folding.
func foldSlice(nodes []string) string {
	if len(nodes) == 0 {
		return ""
	}
	nodes = dedupeSorted(nodes)
	// Group by prefix (part before trailing digits)
	groups := groupByPrefix(nodes)
	var parts []string
	for _, prefix := range sortedPrefixes(groups) {
		indices := groups[prefix]
		if len(indices) == 0 {
			parts = append(parts, prefix) // single node name, no bracket (e.g. localhost)
		} else {
			parts = append(parts, prefix+"["+rangeString(indices)+"]")
		}
	}
	return strings.Join(parts, ",")
}

func dedupeSorted(nodes []string) []string {
	if len(nodes) == 0 {
		return nodes
	}
	sort.Slice(nodes, func(i, j int) bool { return nodeLess(nodes[i], nodes[j]) })
	out := nodes[:1]
	for i := 1; i < len(nodes); i++ {
		if nodes[i] != out[len(out)-1] {
			out = append(out, nodes[i])
		}
	}
	return out
}

func groupByPrefix(nodes []string) map[string][]int {
	groups := make(map[string][]int)
	for _, n := range nodes {
		prefix, num := splitNodeName(n)
		if num < 0 {
			// no numeric suffix: treat as single node, use empty key and store as -1 or use special
			// represent as prefix="", we need a key. Use the full name and store no indices; output as single.
			// Actually for "localhost" we want "localhost". So group by full name when no suffix.
			groups[n] = []int{} // signal: single node, no bracket
			continue
		}
		groups[prefix] = append(groups[prefix], num)
	}
	return groups
}

func sortedPrefixes(groups map[string][]int) []string {
	var keys []string
	for k, idx := range groups {
		if len(idx) == 0 {
			keys = append(keys, k) // single node like "localhost"
		} else {
			keys = append(keys, k)
		}
	}
	sort.Slice(keys, func(i, j int) bool { return keys[i] < keys[j] })
	return keys
}

// rangeString formats a sorted list of indices as "1-3,5,7-9" (inner part only; caller adds brackets).
func rangeString(indices []int) string {
	if len(indices) == 0 {
		return ""
	}
	sort.Ints(indices)
	if len(indices) == 1 {
		return strconv.Itoa(indices[0])
	}
	// try to use /step if evenly spaced
	if step := detectStep(indices); step > 1 {
		return strconv.Itoa(indices[0]) + "-" + strconv.Itoa(indices[len(indices)-1]) + "/" + strconv.Itoa(step)
	}
	var parts []string
	i := 0
	for i < len(indices) {
		start := indices[i]
		end := start
		for i+1 < len(indices) && indices[i+1] == indices[i]+1 {
			i++
			end = indices[i]
		}
		if start == end {
			parts = append(parts, strconv.Itoa(start))
		} else {
			parts = append(parts, strconv.Itoa(start)+"-"+strconv.Itoa(end))
		}
		i++
	}
	return strings.Join(parts, ",")
}

func detectStep(indices []int) int {
	if len(indices) < 2 {
		return 0
	}
	s := indices[1] - indices[0]
	if s <= 0 {
		return 0
	}
	for i := 2; i < len(indices); i++ {
		if indices[i]-indices[i-1] != s {
			return 0
		}
	}
	return s
}
