# Cross-agent gateway

ChatGPT Work, Claude Cowork/Code, Grok Build가 서로를 **서브에이전트**로 부르게 하는 구성입니다.

핵심은 한 줄입니다.

> ChatGPT Work와 Claude Cowork의 커스텀 커넥터는 **사용자 PC가 아니라 OpenAI/Anthropic 클라우드에서 HTTPS로 붙습니다.**  
> 그래서 항상 켜져 있는 **Hostinger VPS에 Streamable HTTP MCP**를 올립니다.  
> 로컬은 CLI 플러그인으로 같은 일을 더 빠르게 합니다.

```
ChatGPT Work  ──MCP HTTPS──┐
Claude Cowork ──MCP HTTPS──┼──► Hostinger VPS
Grok / Claude Code CLI ────┘      FastMCP :8787
                                  Caddy :443 + Bearer
                                  claude / codex / grok CLI
```

자세한 설치는 동봉한 zip / 로컬 artifacts를 보십시오.
