// screenreader-mcp -- the entry point.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entry point only: parse flags, hand them to wiring, run.
//
// Only --version and --print-default-config write to stdout, and they exit before any MCP frame.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	"github.com/marlon-sousa/screen-readers-mcp/server/config"
	"github.com/marlon-sousa/screen-readers-mcp/server/version"
	"github.com/marlon-sousa/screen-readers-mcp/server/wiring"
)

// readerFlags preserves the order given, which is the order a reader's endpoints are tried in.
type readerFlags []string

func (f *readerFlags) String() string { return fmt.Sprint(*f) }

func (f *readerFlags) Set(value string) error {
	*f = append(*f, value)
	return nil
}

func main() {
	var readers readerFlags
	flag.Var(&readers, "reader",
		"name=spec endpoint override, repeatable and highest precedence "+
			"(e.g. nvda=local:nvdaMcpBridge or talkback=tcp:127.0.0.1:9010)")
	configPath := flag.String("config", "",
		"path to a JSON file replacing or extending the embedded reader defaults")
	printDefaults := flag.Bool("print-default-config", false,
		"print the embedded reader defaults and exit")
	showVersion := flag.Bool("version", false, "print the version and exit")
	verbose := flag.Bool("verbose", false, "log debug detail to stderr")
	flag.Parse()

	if *showVersion {
		fmt.Println(version.Version)
		return
	}
	if *printDefaults {
		os.Stdout.Write(config.DefaultsJSON())
		return
	}

	server, err := wiring.Build(wiring.Options{
		ConfigPath:  *configPath,
		ReaderFlags: readers,
		Verbose:     *verbose,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "screenreader-mcp: %v\n", err)
		os.Exit(1)
	}

	if err := server.Run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "screenreader-mcp: %v\n", err)
		os.Exit(1)
	}
}
