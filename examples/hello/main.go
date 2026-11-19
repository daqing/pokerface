// The hello service (examples/hello): one static binary, no dependencies —
// the whole image is this file plus nothing else, built FROM scratch.
package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	message := getenv("HELLO_MESSAGE", "hello from a pokerface-built image")
	commit := getenv("HELLO_COMMIT", "")
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		if commit != "" {
			fmt.Fprintf(w, "%s (built from %s)\n", message, commit)
			return
		}
		fmt.Fprintf(w, "%s\n", message)
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintln(w, "ok")
	})
	port := getenv("PORT", "8080")
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func getenv(name, fallback string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return fallback
}
