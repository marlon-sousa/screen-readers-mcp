# nvda-mcp (server)

The MCP server half of nvda-mcp. It speaks MCP over **stdio** to an AI agent
(Claude Code, ...) and translates each tool call into a JSON-lines command sent
over loopback TCP to the **nvdaMcpBridge** NVDA addon, which drives NVDA and
captures what it speaks and brailles.

Status: **skeleton** (milestone 4 builds the FastMCP app and the v1 tools).

## Dev workflow

```
uv run --directory server nvda-mcp      # run the server (once implemented)
uv run --directory server pytest        # tests (no NVDA required; fake bridge)
uv run --directory server pyright       # strict type-check
```

Wire into Claude Code from source:

```
claude mcp add --scope user nvda -- uv run --directory C:\projects\nvda-mcp\server nvda-mcp
```

The shared wire contract lives in the sibling `shared/` package
(`nvda-mcp-wire`); this server depends on it via a path source in
`pyproject.toml`.
