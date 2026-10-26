// Package ids makes random identifiers, tokens and PINs.
package ids

import (
	"crypto/rand"
	"encoding/hex"
	"math/big"
)

// Hex returns n random bytes hex-encoded.
func Hex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

// Token is an opaque bearer token.
func Token() string { return Hex(16) }

// Digits returns n random decimal digits; the first one is never 0.
func Digits(n int) string {
	out := make([]byte, n)
	for i := range out {
		lo := int64(0)
		if i == 0 {
			lo = 1
		}
		v, err := rand.Int(rand.Reader, big.NewInt(10-lo))
		if err != nil {
			panic(err)
		}
		out[i] = byte('0' + lo + v.Int64())
	}
	return string(out)
}
