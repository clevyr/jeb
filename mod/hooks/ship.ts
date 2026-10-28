// Whether a shell command ships something: a commit or push, a PR opened or
// merged, a release, a publish, or a deploy. Quoted strings and heredoc bodies
// are blanked first and each `&&`/`;`/`|` segment is judged on its own, so
// `echo "git push"` does not count.

const SHIPPING: RegExp[] = [
  /^git\s+(?:-C\s+\S+\s+)?(?:commit|push)\b/,
  /^gh\s+pr\s+(?:create|merge)\b/,
  /^gh\s+release\s+create\b/,
  /^(?:npm|pnpm|yarn)\s+publish\b/,
  /^docker\s+push\b/,
  /^helm\s+(?:upgrade|install)\b/,
  /^kubectl\s+apply\b/,
  /^fly\s+deploy\b/,
  /^(?:vercel|netlify)\b.*--prod\b/,
  // A script or target that is itself called `deploy`, and nothing looser.
  /^(?:(?:npm|pnpm|bun)\s+run|yarn(?:\s+run)?|make)\s+deploy(?=\s|$)/,
]

// A script called `deploy` or `deploy.sh`, by its basename: not `undeploy.sh`,
// `deploy-check` or `preview-deploy-cleanup`.
const DEPLOY_SCRIPT = /^deploy(?:\.sh)?$/

const WRAPPERS = new Set(['sudo', 'rtk', 'proxy'])

const HEREDOC = /<<-?\s*(['"]?)([A-Za-z_]\w*)\1/

// The command with heredoc bodies removed and quoted strings emptied.
export const stripQuoted = (command: string) => {
  const kept: string[] = []
  let closer: string | undefined

  for (const line of command.split('\n')) {
    if (closer !== undefined) {
      if (line.trim() === closer) {
        closer = undefined
      }
      continue
    }
    kept.push(line)
    closer = HEREDOC.exec(line)?.[2]
  }

  return kept
    .join('\n')
    .replace(/"(?:\\.|[^"\\])*"/g, '""')
    .replace(/'[^']*'/g, "''")
}

// Each `&&`/`||`/`;`/`|`/newline segment as words, quoted text already blanked.
export const segmentsOf = (command: string) =>
  stripQuoted(command)
    .split(/&&|\|\||[;|\n]/)
    .map(segment => segment.trim().split(/\s+/).filter(Boolean))

// Leading `VAR=value` assignments, `sudo` and the rtk proxy (`rtk git push`,
// `rtk proxy git push`) are not the command.
export const commandOf = (words: string[]) => {
  const rest = [...words]
  while (rest[0] && (/^\w+=/.test(rest[0]) || WRAPPERS.has(rest[0]))) {
    rest.shift()
  }

  return rest
}

const isShipSegment = (segment: string[]) => {
  const words = commandOf(segment)
  const name = (words[0] ?? '').split('/').pop() ?? ''

  return SHIPPING.some(pattern => pattern.test(words.join(' '))) || DEPLOY_SCRIPT.test(name)
}

export const isShip = (command: string) => segmentsOf(command).some(isShipSegment)

