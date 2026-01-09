package search

import "testing"

func TestFindClosestTest(t *testing.T) {
	candidates := []string{
		"foo.bar",
		"foo.long.bar",
		"other.test",
	}

	tests := []struct {
		name      string
		pattern   string
		want      string
		wantFound bool
	}{
		{
			name:      "exact match",
			pattern:   "foo.bar",
			want:      "foo.bar",
			wantFound: true,
		},
		{
			name:      "subsequence match (short alias)",
			pattern:   "f.l.b",
			want:      "foo.long.bar",
			wantFound: true,
		},
		{
			name:      "typo match (Levenshtein)",
			pattern:   "foo.baz",
			want:      "foo.bar",
			wantFound: true,
		},
		{
			name:      "no match",
			pattern:   "nomatch",
			want:      "",
			wantFound: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, found := FindClosestTest(tt.pattern, candidates)
			if found != tt.wantFound {
				t.Errorf("FindClosestTest() found = %v, want %v", found, tt.wantFound)
			}
			if got != tt.want {
				t.Errorf("FindClosestTest() got = %v, want %v", got, tt.want)
			}
		})
	}
}
