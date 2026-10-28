import { RADIO_LINE } from './anonymize'

// MCP tools: the server in a tool's name decides Jeb's pose and line. A server
// Jeb does not know gets the radio and a plain line: its name is never said.

export type McpKind = { glyph: string; line: string }

// First match wins; each pattern is tested against the server's name, lower case.
const TABLE: [RegExp, McpKind][] = [
  [/atlassian|jira|confluence/, { glyph: '📋', line: "Checkin' the work board" }],
  [/sentry/, { glyph: '🐛', line: "Huntin' bugs in the corn" }],
  [/slack/, { glyph: '📞', line: 'On the party line' }],
  [/chrome|browser/, { glyph: '🔭', line: "Lookin' down the holler" }],
  [/figma|design/, { glyph: '🎨', line: "Paintin' the barn" }],
  [/gmail|calendar|mail/, { glyph: '📫', line: "Checkin' the mailbox" }],
  [/docs|drive/, { glyph: '📜', line: "Readin' the deed" }],
]

export const UNKNOWN_GLYPH = '📻'

// The server of an `mcp__<server>__<tool>` name, or undefined for any other tool.
export const mcpServerOf = (tool: string): string | undefined => {
  if (!tool.startsWith('mcp__')) {
    return undefined
  }
  const rest = tool.slice(5)
  const at = rest.indexOf('__')
  const server = at < 0 ? rest : rest.slice(0, at)

  return server === '' ? undefined : server
}

// What Jeb does for a server: a known one's pose and line, else the radio.
export const mcpKindOf = (server: string): McpKind => {
  const name = server.toLowerCase()
  const hit = TABLE.find(([pattern]) => pattern.test(name))

  return hit ? hit[1] : { glyph: UNKNOWN_GLYPH, line: RADIO_LINE }
}

// Every line this module can say, for the glyph checks.
export const MCP_LINES = [...TABLE.map(([, kind]) => kind.line), RADIO_LINE]
