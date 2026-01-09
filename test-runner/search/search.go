package search

import (
	"sort"

	"github.com/lithammer/fuzzysearch/fuzzy"
)

// FindClosestTest returns the closest match from candidates to the pattern.
// It uses fuzzy matching (subsequence) first, then falls back to Levenshtein distance.
func FindClosestTest(pattern string, candidates []string) (string, bool) {
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
