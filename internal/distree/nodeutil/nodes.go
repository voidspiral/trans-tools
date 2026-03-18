// Package nodeutil 提供节点列表的解析与分组工具，供 distree 客户端和服务端使用。
// 不引用 myclush 任何包。
package nodeutil

import (
	"strings"

	"github.com/iskylite/nodeset"
)

// NodeAddr 表示一个节点及其可选端口。
// 若 Port 为空，调用方应使用协议级别的默认端口。
type NodeAddr struct {
	Host string
	Port string // 空表示使用默认端口
}

// Expand 将逗号分隔或 nodeset 表达式展开为 NodeAddr 列表。
// 支持两种格式（可混用）：
//   - "cn1,cn2,cn3"         → 各节点 Port 为空，使用默认端口
//   - "cn1:19951,cn2:19952" → 各节点使用指定端口（单机多端口测试场景）
//
// nodeset 表达式（如 "cn[1-3]"）展开后所有节点 Port 均为空。
func Expand(expr string) []NodeAddr {
	expr = strings.TrimSpace(expr)
	if expr == "" {
		return nil
	}

	// 先按逗号切分，逐段判断是否含端口
	parts := splitRaw(expr)
	var addrs []NodeAddr
	for _, part := range parts {
		if idx := strings.LastIndex(part, ":"); idx > 0 {
			// 含冒号且冒号后看起来是端口（纯数字）
			host, port := part[:idx], part[idx+1:]
			if isPort(port) {
				addrs = append(addrs, NodeAddr{Host: host, Port: port})
				continue
			}
		}
		// 没有端口：尝试 nodeset 展开
		expanded := expandNodeset(part)
		for _, h := range expanded {
			addrs = append(addrs, NodeAddr{Host: h, Port: ""})
		}
	}
	return addrs
}

// Hosts 从 NodeAddr 列表中提取纯主机名（不含端口）。
func Hosts(addrs []NodeAddr) []string {
	out := make([]string, len(addrs))
	for i, a := range addrs {
		out[i] = a.Host
	}
	return out
}

// SplitByWidth 将 NodeAddr 列表按宽度 width 分成多组。
// 每组由"第一个节点"作为下一跳网关，其余节点继续在该节点的 nodelist 中下传。
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
// Host 为空的 NodeAddr 会被跳过。
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

// splitRaw 按逗号切分，但跳过空段；不做 nodeset 展开。
func splitRaw(s string) []string {
	var out []string
	for _, part := range strings.Split(s, ",") {
		if v := strings.TrimSpace(part); v != "" {
			out = append(out, v)
		}
	}
	return out
}

func expandNodeset(s string) []string {
	iter, err := nodeset.Yield(s)
	if err != nil || iter == nil {
		return []string{s}
	}
	var nodes []string
	for iter.Next() {
		nodes = append(nodes, iter.Value())
	}
	if len(nodes) == 0 {
		return []string{s}
	}
	return nodes
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
