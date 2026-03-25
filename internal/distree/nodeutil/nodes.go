// Package nodeutil 提供节点列表的解析与分组工具，供 distree 客户端和服务端使用。
package nodeutil

import (
	"strings"

	"github.com/iskylite/nodeset"
)

// NodeAddr 表示一个节点及其可选端口。
type NodeAddr struct {
	Host string
	Port string
}

// Expand 将逗号分隔或 nodeset 表达式展开为 NodeAddr 列表。
// 支持两种格式（可混用）：
//   - "cn[1-3,5-7]"           → nodeset 展开，Port 为空
//   - "cn1:19951,cn2:19952"   → 各节点使用指定端口（单机测试场景）
//   - "cn[1-3]:2007"          → nodeset 展开后每个节点统一使用 2007
//   - 混合 "cn[1-3],h1:8080" → 分段处理
//
// 逗号是顶层分隔符，但方括号内的逗号不拆分（与 ClusterShell 一致）。
func Expand(expr string) []NodeAddr {
	expr = strings.TrimSpace(expr)
	if expr == "" {
		return nil
	}

	segments := splitTopLevel(expr)
	var addrs []NodeAddr
	for _, seg := range segments {
		// 检查是否有 host:port 格式（冒号在方括号外、且冒号后面是纯数字）
		if host, port, ok := splitHostPort(seg); ok {
			expanded := expandNodeset(host)
			for _, h := range expanded {
				addrs = append(addrs, NodeAddr{Host: h, Port: port})
			}
			continue
		}
		expanded := expandNodeset(seg)
		for _, h := range expanded {
			addrs = append(addrs, NodeAddr{Host: h, Port: ""})
		}
	}
	return addrs
}

// Hosts 从 NodeAddr 列表中提取纯主机名。
func Hosts(addrs []NodeAddr) []string {
	out := make([]string, len(addrs))
	for i, a := range addrs {
		out[i] = a.Host
	}
	return out
}

// SplitByWidth 将 NodeAddr 列表按宽度 width 分成多组。
func SplitByWidth(addrs []NodeAddr, width int) [][]NodeAddr {
	if width <= 0 {
		width = 1
	}
	var groups [][]NodeAddr
	for i := 0; i < len(addrs); i += width {
		end := i + width
		if end > len(addrs) {
			end = len(addrs)
		}
		groups = append(groups, addrs[i:end])
	}
	return groups
}

// Join 将 NodeAddr 列表重新序列化为逗号分隔字符串，保留端口信息。
func Join(addrs []NodeAddr) string {
	var parts []string
	for _, a := range addrs {
		if a.Host == "" {
			continue
		}
		if a.Port != "" {
			parts = append(parts, a.Host+":"+a.Port)
		} else {
			parts = append(parts, a.Host)
		}
	}
	return strings.Join(parts, ",")
}

// ResolvePort 返回节点的实际端口：若节点自身携带端口则优先使用，否则使用 defaultPort。
func ResolvePort(addr NodeAddr, defaultPort string) string {
	if addr.Port != "" {
		return addr.Port
	}
	return defaultPort
}

// --------- 私有辅助 ---------

// splitTopLevel 按顶层逗号切分字符串，方括号内的逗号不拆分。
// 例如 "cn[1-3,5],h1:8080" → ["cn[1-3,5]", "h1:8080"]
func splitTopLevel(s string) []string {
	var result []string
	depth := 0
	start := 0
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '[':
			depth++
		case ']':
			if depth > 0 {
				depth--
			}
		case ',':
			if depth == 0 {
				seg := strings.TrimSpace(s[start:i])
				if seg != "" {
					result = append(result, seg)
				}
				start = i + 1
			}
		}
	}
	if seg := strings.TrimSpace(s[start:]); seg != "" {
		result = append(result, seg)
	}
	return result
}

// splitHostPort 尝试将 "expr:port" 拆分，其中 port 是纯数字且冒号在方括号外。
// "cn[1-3]:2007" → ("cn[1-3]", "2007", true)
// "cn[1-3]"      → ("", "", false)
// "cn[1-3,5:7]"  → ("", "", false)  冒号在括号内
func splitHostPort(s string) (host, port string, ok bool) {
	depth := 0
	lastColon := -1
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case '[':
			depth++
		case ']':
			if depth > 0 {
				depth--
			}
		case ':':
			if depth == 0 {
				lastColon = i
			}
		}
	}
	if lastColon <= 0 || lastColon >= len(s)-1 {
		return "", "", false
	}
	p := s[lastColon+1:]
	if !isPort(p) {
		return "", "", false
	}
	return s[:lastColon], p, true
}

func expandNodeset(s string) []string {
	ns, err := nodeset.Expand(s)
	if err != nil || len(ns) == 0 {
		return []string{s}
	}
	return ns
}

func isPort(s string) bool {
	if s == "" || len(s) > 5 {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
