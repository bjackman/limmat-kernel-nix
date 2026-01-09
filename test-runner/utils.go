package main

import (
	"sort"

	"github.com/lithammer/fuzzysearch/fuzzy"
)

// findClosestTest returns the closest match from candidates to the pattern.
// It uses fuzzy matching (subsequence) first, then falls back to Levenshtein distance.
func findClosestTest(pattern string, candidates []string) (string, bool) {
	// 1. Try fuzzy subsequence matching first (handles "foo.bar" -> "foo.long.bar")
	matches := fuzzy.RankFind(pattern, candidates)
	if len(matches) > 0 {
		sort.Slice(matches, func(i, j int) bool {
			if matches[i].Distance == matches[j].Distance {
				return len(matches[i].Target) < len(matches[j].Target)
			}
			return matches[i].Distance < matches[j].Distance
		})
		return matches[0].Target, true
	}

	// 2. Fallback to Levenshtein distance for typos (handles "foo.baz" -> "foo.bar")
	// We manually iterate because fuzzy.RankFind doesn't do Levenshtein.
	// We use fuzzy.LevenshteinDistance from the library implicitly if we import the subpackage,
	// but let's see if we can just do a simple search.
	// Actually, let's just use the `fuzzy` package's LevenshteinDistance if exposed,
	// or `fuzzy.Levenshtein` function?
	// Checking the library docs (or guessing): `fuzzy.LevenshteinDistance` usually exists.
	// Let's implement a manual search using `fuzzy.LevenshteinDistance`.

	bestMatch := ""
	minDist := -1

	for _, c := range candidates {
		dist := fuzzy.LevenshteinDistance(pattern, c)

		// Threshold logic similar to before: allow changes up to 50% of length
		limit := len(c) / 2
		if limit < 2 {
			limit = 2
		}

		if dist < limit {
			if minDist == -1 || dist < minDist {
				minDist = dist
				bestMatch = c
			}
		}
	}

	if minDist != -1 {
		return bestMatch, true
	}

	return "", false
}
