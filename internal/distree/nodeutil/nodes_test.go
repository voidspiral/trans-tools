package nodeutil

import (
	"fmt"
	"testing"
)

func TestExpand_SimpleRange(t *testing.T) {
	addrs := Expand("cn[1-3]")
	want := []string{"cn1", "cn2", "cn3"}
	assertHosts(t, addrs, want)
}

func TestExpand_CommaInsideBrackets(t *testing.T) {
	addrs := Expand("cn[32-33,35-39]")
	want := []string{"cn32", "cn33", "cn35", "cn36", "cn37", "cn38", "cn39"}
	assertHosts(t, addrs, want)
}

func TestExpand_ComplexBrackets(t *testing.T) {
	addrs := Expand("cn[32-33,35-39,44-47,96-97,99-109,111-115,118-125]")
	if len(addrs) == 0 {
		t.Fatal("expected non-empty result")
	}
	// cn32,cn33 = 2; cn35-39 = 5; cn44-47 = 4; cn96-97 = 2; cn99-109 = 11; cn111-115 = 5; cn118-125 = 8
	// total = 2+5+4+2+11+5+8 = 37
	if got := len(addrs); got != 37 {
		t.Errorf("len = %d, want 37; hosts: %v", got, Hosts(addrs))
	}
}

func TestExpand_SingleValues(t *testing.T) {
	addrs := Expand("cn[1,3,5]")
	want := []string{"cn1", "cn3", "cn5"}
	assertHosts(t, addrs, want)
}

func TestExpand_PlainCommaList(t *testing.T) {
	addrs := Expand("cn1,cn2,cn3")
	want := []string{"cn1", "cn2", "cn3"}
	assertHosts(t, addrs, want)
}

func TestExpand_HostPort(t *testing.T) {
	addrs := Expand("cn1:2007,cn2:2008")
	if len(addrs) != 2 {
		t.Fatalf("len = %d, want 2", len(addrs))
	}
	if addrs[0].Host != "cn1" || addrs[0].Port != "2007" {
		t.Errorf("addrs[0] = %+v, want cn1:2007", addrs[0])
	}
	if addrs[1].Host != "cn2" || addrs[1].Port != "2008" {
		t.Errorf("addrs[1] = %+v, want cn2:2008", addrs[1])
	}
}

func TestExpand_NodesetWithPort(t *testing.T) {
	addrs := Expand("cn[1-3]:2007")
	want := []string{"cn1", "cn2", "cn3"}
	assertHosts(t, addrs, want)
	for _, a := range addrs {
		if a.Port != "2007" {
			t.Errorf("host %s port = %q, want 2007", a.Host, a.Port)
		}
	}
}

func TestExpand_Mixed(t *testing.T) {
	addrs := Expand("cn[1-3],h1:8080,gpu[10-12]")
	// cn1,cn2,cn3, h1:8080, gpu10,gpu11,gpu12 = 7
	if len(addrs) != 7 {
		t.Fatalf("len = %d, want 7; addrs: %v", len(addrs), addrs)
	}
	if addrs[3].Host != "h1" || addrs[3].Port != "8080" {
		t.Errorf("addrs[3] = %+v, want h1:8080", addrs[3])
	}
}

func TestExpand_Empty(t *testing.T) {
	addrs := Expand("")
	if len(addrs) != 0 {
		t.Errorf("expected empty, got %v", addrs)
	}
}

func TestExpand_SingleHost(t *testing.T) {
	addrs := Expand("cn32")
	assertHosts(t, addrs, []string{"cn32"})
}

func TestSplitTopLevel(t *testing.T) {
	tests := []struct {
		input string
		want  []string
	}{
		{"cn[1-3,5],h1:8080", []string{"cn[1-3,5]", "h1:8080"}},
		{"cn[1-3]", []string{"cn[1-3]"}},
		{"a,b,c", []string{"a", "b", "c"}},
		{"cn[1,2-5,7],gpu[10-12]:8080,h1", []string{"cn[1,2-5,7]", "gpu[10-12]:8080", "h1"}},
	}
	for _, tt := range tests {
		got := splitTopLevel(tt.input)
		if fmt.Sprintf("%v", got) != fmt.Sprintf("%v", tt.want) {
			t.Errorf("splitTopLevel(%q) = %v, want %v", tt.input, got, tt.want)
		}
	}
}

func TestJoinRoundTrip(t *testing.T) {
	addrs := []NodeAddr{
		{Host: "cn1", Port: ""},
		{Host: "cn2", Port: "2007"},
		{Host: "cn3", Port: ""},
	}
	got := Join(addrs)
	want := "cn1,cn2:2007,cn3"
	if got != want {
		t.Errorf("Join = %q, want %q", got, want)
	}
}

func assertHosts(t *testing.T, addrs []NodeAddr, want []string) {
	t.Helper()
	got := Hosts(addrs)
	if len(got) != len(want) {
		t.Fatalf("len = %d, want %d; got %v", len(got), len(want), got)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Errorf("[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}
