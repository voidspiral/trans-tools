package nodeset

import (
	"sort"
	"strconv"
	"strings"
	"unicode"
)

// op is set operation for extended pattern (left-to-right).
type op int

const (
	opUnion op = iota
	opDiff
	opIntersect
	opXor
)

func (o op) apply(current, next map[string]struct{}) map[string]struct{} {
	out := make(map[string]struct{}, len(current))
	switch o {
	case opUnion:
		for n := range current {
			out[n] = struct{}{}
		}
		for n := range next {
			out[n] = struct{}{}
		}
	case opDiff:
		for n := range current {
			if _, ok := next[n]; !ok {
				out[n] = struct{}{}
			}
		}
	case opIntersect:
		for n := range current {
			if _, ok := next[n]; ok {
				out[n] = struct{}{}
			}
		}
	case opXor:
		for n := range current {
			if _, ok := next[n]; !ok {
				out[n] = struct{}{}
			}
		}
		for n := range next {
			if _, ok := current[n]; !ok {
				out[n] = struct{}{}
			}
		}
	}
	return out
}

// segment holds one operand and the operation that precedes it (for left-to-right eval).
type segment struct {
	op  op
	pat string
}

// parseExtended splits pattern by operators , ! & ^ (only when not inside []) and returns segments.
func parseExtended(pat string) ([]segment, error) {
	pat = strings.TrimSpace(pat)
	if pat == "" {
		return []segment{{op: opUnion, pat: ""}}, nil
	}
	var segs []segment
	start := 0
	currentOp := opUnion // op applied between previous result and the next operand
	inBracket := 0
	for i := 0; i < len(pat); i++ {
		switch pat[i] {
		case '[':
			inBracket++
		case ']':
			inBracket--
		case ',', '!', '&', '^':
			if inBracket == 0 {
				nextOp := opUnion
				switch pat[i] {
				case ',':
					nextOp = opUnion
				case '!':
					nextOp = opDiff
				case '&':
					nextOp = opIntersect
				case '^':
					nextOp = opXor
				}
				seg := strings.TrimSpace(pat[start:i])
				if seg != "" {
					segs = append(segs, segment{op: currentOp, pat: seg})
				}
				start = i + 1
				currentOp = nextOp
			}
		}
	}
	seg := strings.TrimSpace(pat[start:])
	if seg != "" {
		segs = append(segs, segment{op: currentOp, pat: seg})
	}
	if len(segs) == 0 {
		segs = append(segs, segment{op: opUnion, pat: pat})
	}
	return segs, nil
}

// expandSegment expands a single range expression (no operators) to a set of node names.
// E.g. "node[1-5]", "node[1,3,5]", "node[1-10/2]", "localhost".
func expandSegment(seg string) (map[string]struct{}, error) {
	seg = strings.TrimSpace(seg)
	if seg == "" {
		return map[string]struct{}{}, nil
	}
	idx := strings.Index(seg, "[")
	if idx < 0 {
		return map[string]struct{}{seg: {}}, nil
	}
	prefix := seg[:idx]
	rest := seg[idx:]
	if len(rest) < 2 || rest[0] != '[' || rest[len(rest)-1] != ']' {
		return map[string]struct{}{seg: {}}, nil
	}
	inner := strings.TrimSpace(rest[1 : len(rest)-1])
	if inner == "" {
		return map[string]struct{}{}, nil
	}
	// Parse comma-separated range parts: 1-5, 1,3, 1-10/2
	parts := splitUnbracketed(inner, ',')
	var indices []int
	seen := make(map[int]struct{})
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		nums, err := parseRangePart(p)
		if err != nil {
			return nil, err
		}
		for _, n := range nums {
			if _, ok := seen[n]; !ok {
				seen[n] = struct{}{}
				indices = append(indices, n)
			}
		}
	}
	sort.Ints(indices)
	out := make(map[string]struct{}, len(indices))
	for _, n := range indices {
		out[prefix+strconv.Itoa(n)] = struct{}{}
	}
	return out, nil
}

// parseRangePart parses one part like "1-5", "3", "1-10/2" and returns sorted unique indices.
func parseRangePart(p string) ([]int, error) {
	p = strings.TrimSpace(p)
	step := 1
	if idx := strings.Index(p, "/"); idx >= 0 {
		s, err := strconv.Atoi(strings.TrimSpace(p[idx+1:]))
		if err != nil || s < 1 {
			return nil, err
		}
		step = s
		p = strings.TrimSpace(p[:idx])
	}
	if strings.Contains(p, "-") {
		idx := strings.Index(p, "-")
		lo, err1 := strconv.Atoi(strings.TrimSpace(p[:idx]))
		hi, err2 := strconv.Atoi(strings.TrimSpace(p[idx+1:]))
		if err1 != nil || err2 != nil {
			return nil, strconv.ErrSyntax
		}
		if lo > hi {
			lo, hi = hi, lo
		}
		var out []int
		for i := lo; i <= hi; i += step {
			out = append(out, i)
		}
		return out, nil
	}
	n, err := strconv.Atoi(p)
	if err != nil {
		return nil, err
	}
	return []int{n}, nil
}

// splitUnbracketed splits s by sep but only when not inside brackets.
func splitUnbracketed(s string, sep rune) []string {
	var parts []string
	var buf strings.Builder
	depth := 0
	for _, r := range s {
		if r == '[' {
			depth++
			buf.WriteRune(r)
		} else if r == ']' {
			depth--
			buf.WriteRune(r)
		} else if r == sep && depth == 0 {
			parts = append(parts, buf.String())
			buf.Reset()
		} else {
			buf.WriteRune(r)
		}
	}
	if buf.Len() > 0 {
		parts = append(parts, buf.String())
	}
	return parts
}

// ParseExpand parses the pattern (including extended , ! & ^) and returns sorted unique node list.
func ParseExpand(pat string) ([]string, error) {
	segs, err := parseExtended(pat)
	if err != nil {
		return nil, err
	}
	set := make(map[string]struct{})
	for i, s := range segs {
		next, err := expandSegment(s.pat)
		if err != nil {
			return nil, err
		}
		if i == 0 {
			set = s.op.apply(set, next) // first op is opUnion by construction
		} else {
			set = s.op.apply(set, next)
		}
	}
	list := make([]string, 0, len(set))
	for n := range set {
		list = append(list, n)
	}
	sort.Slice(list, func(i, j int) bool {
		return nodeLess(list[i], list[j])
	})
	return list, nil
}

// nodeLess orders node names: compare prefix (alpha), then numeric suffix.
func nodeLess(a, b string) bool {
	preA, numA := splitNodeName(a)
	preB, numB := splitNodeName(b)
	if preA != preB {
		return preA < preB
	}
	return numA < numB
}

// splitNodeName returns prefix (before trailing digits) and numeric suffix (or -1 if none).
func splitNodeName(s string) (string, int) {
	i := len(s) - 1
	for i >= 0 && unicode.IsDigit(rune(s[i])) {
		i--
	}
	if i == len(s)-1 {
		return s, -1
	}
	if i < 0 {
		n, _ := strconv.Atoi(s)
		return "", n
	}
	prefix := s[:i+1]
	n, _ := strconv.Atoi(s[i+1:])
	return prefix, n
}
