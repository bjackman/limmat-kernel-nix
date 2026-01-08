package main

// levenshtein calculates the Levenshtein distance between two strings.
func levenshtein(s1, s2 string) int {
	if len(s1) == 0 {
		return len(s2)
	}
	if len(s2) == 0 {
		return len(s1)
	}

	// Optimization: Swap to use smaller string for columns
	if len(s1) > len(s2) {
		s1, s2 = s2, s1
	}

	row := make([]int, len(s1)+1)
	for i := 0; i <= len(s1); i++ {
		row[i] = i
	}

	for j := 1; j <= len(s2); j++ {
		prevRow := row[0]
		row[0] = j
		for i := 1; i <= len(s1); i++ {
			cost := 1
			if s1[i-1] == s2[j-1] {
				cost = 0
			}
			newVal := min(
				row[i-1]+1,     // insertion
				row[i]+1,       // deletion
				prevRow+cost, // substitution
			)
			prevRow = row[i]
			row[i] = newVal
		}
	}

	return row[len(s1)]
}

func min(vals ...int) int {
	m := vals[0]
	for _, v := range vals[1:] {
		if v < m {
			m = v
		}
	}
	return m
}

// findClosestTest returns the closest match from candidates to the pattern.
// It returns true if a match is found within the threshold.
func findClosestTest(pattern string, candidates []string) (string, bool) {
	bestMatch := ""
	minDist := -1

	for _, c := range candidates {
		dist := levenshtein(pattern, c)
		// Threshold: allow some fuzziness.
		// For example, distance should be less than 50% of the longer string length?
		// Or a fixed threshold?
		// Let's use a combination.
		// If string is short (< 5 chars), allow 1 or 2 edits.
		// If string is long, allow more.

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
