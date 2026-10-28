// What a shell command is, in the terms of the workday: a test run, a lint or
// analysis run, something run inside a Docker Compose service, or a deny-rule
// match. Pure. It reads the same segments `ship.ts` does (quoted text and
// heredoc bodies blanked, each `&&`/`;`/`|` part judged alone), unwraps `rtk`,
// `sudo`, env prefixes and `docker compose exec|run`, and costs O(length).

import { commandOf, segmentsOf, stripQuoted } from './ship'

export type SegmentKind = 'test' | 'lint' | 'exec' | 'worktree' | 'none'

// The commands the user's deny rules refuse.
export type DenyRule = 'reset' | 'force' | 'down' | 'rmrf' | 'clean'

export type Segment = {
  kind: SegmentKind
  // The Compose service the command runs in (exec, run, up).
  svc?: string
  // A test run narrowed with --filter, --group or a tests/ path (never --parallel).
  filtered?: boolean
  // Which tool: 'artisan', 'pest', 'phpunit', 'composer:analyse', 'pint', 'npm:lint', ...
  tool?: string
  // The artisan command or the Compose verb ('migrate:status', 'exec', 'up', 'run', 'down').
  sub?: string
  // `compose up -d` and `compose run --rm`.
  detached?: boolean
  rm?: boolean
  // A lint that rewrites files (pint without --test, eslint --fix): no pass verdict.
  fixes?: boolean
  deny?: DenyRule
  // The last segment of the command: the only one whose exit code is the call's.
  isLast: boolean
}

type Found = Omit<Segment, 'isLast'>

const NONE: Found = { kind: 'none' }

const base = (word: string | undefined) => (word ?? '').split('/').pop() ?? ''

const isFlag = (word: string) => word.startsWith('-')

// The first word that is neither a flag nor a flag's value; `valued` names the
// flags that take the next word as theirs.
const skipFlags = (words: readonly string[], valued: ReadonlySet<string>) => {
  let at = 0
  while (at < words.length && isFlag(words[at] as string)) {
    at += valued.has(words[at] as string) ? 2 : 1
  }

  return at
}

const COMPOSE_GLOBAL = new Set(['-f', '--file', '-p', '--project-name', '--profile', '--env-file', '--project-directory', '--ansi', '--parallel'])
const EXEC_VALUED = new Set(['-u', '--user', '-w', '--workdir', '-e', '--env', '--index'])
const RUN_VALUED = new Set([
  '-u', '--user', '-w', '--workdir', '-e', '--env', '--entrypoint', '-v', '--volume',
  '-p', '--publish', '--name', '-l', '--label', '--cap-add', '--cap-drop',
])
const UP_VALUED = new Set(['--scale', '-t', '--timeout', '--pull', '--attach', '--no-attach'])

const hasFlag = (words: readonly string[], long: string, short?: string) =>
  words.some(word => word === long || word.startsWith(`${long}=`) || (short !== undefined && word === short))

const FILTERED_TESTS = /(^|\/)tests\//

const testSegment = (tool: string, args: readonly string[]): Found => {
  const isParallel = hasFlag(args, '--parallel')
  const isNarrow =
    hasFlag(args, '--filter') || hasFlag(args, '--group') || args.some(word => FILTERED_TESTS.test(word))

  return { kind: 'test', tool, sub: 'test', filtered: isNarrow && !isParallel }
}

const lintSegment = (tool: string, sub: string, fixes = false): Found => ({
  kind: 'lint',
  tool,
  sub,
  ...(fixes ? { fixes: true } : {}),
})

const SCRIPTS = new Set(['lint', 'format', 'types', 'typecheck'])
const COMPOSER_LINTS = new Set(['analyse', 'analyze', 'lint'])

// A tool run directly (no Docker): what the words name.
const toolOf = (words: readonly string[]): Found => {
  const name = base(words[0])
  const args = words.slice(1)

  if (name === 'php' || name === 'artisan') {
    const rest = name === 'php' ? (base(args[0]) === 'artisan' ? args.slice(1) : undefined) : args
    if (rest === undefined) {
      return NONE
    }
    const sub = rest.find(word => !isFlag(word))

    return sub === 'test' ? testSegment('artisan', rest) : { kind: 'none', tool: 'artisan', ...(sub ? { sub } : {}) }
  }
  if (name === 'pest' || name === 'phpunit') {
    return testSegment(name, args)
  }
  if (name === 'composer') {
    const sub = args.find(word => !isFlag(word))
    const script = sub === 'run' || sub === 'run-script' ? args[args.indexOf(sub) + 1] : sub
    if (script === 'test') {
      return testSegment('composer', args)
    }

    return script !== undefined && COMPOSER_LINTS.has(script) ? lintSegment(`composer:${script}`, script) : NONE
  }
  if (name === 'pint') {
    const isCheck = hasFlag(args, '--test')

    return lintSegment('pint', isCheck ? 'test' : 'fix', !isCheck)
  }
  if (name === 'phpstan' || name === 'larastan') {
    return lintSegment('phpstan', 'analyse')
  }
  if (name === 'eslint') {
    return lintSegment('eslint', 'check', hasFlag(args, '--fix'))
  }
  if (name === 'prettier') {
    return hasFlag(args, '--check', '-c') ? lintSegment('prettier', 'check') : NONE
  }
  if (name === 'vue-tsc') {
    return lintSegment('vue-tsc', 'check')
  }
  if (name === 'npx' || name === 'bunx') {
    return toolOf(args.slice(skipFlags(args, new Set())))
  }
  if ((name === 'pnpm' || name === 'yarn') && (args[0] === 'exec' || args[0] === 'dlx')) {
    return toolOf(args.slice(1 + skipFlags(args.slice(1), new Set())))
  }
  if (name === 'npm' || name === 'pnpm' || name === 'yarn' || name === 'bun') {
    const script = args[0] === 'run' ? args[1] : name === 'npm' ? undefined : args[0]

    // `format` rewrites files, like pint without --test: no pass verdict.
    return script !== undefined && SCRIPTS.has(script)
      ? lintSegment(`${name}:${script}`, script, script === 'format')
      : NONE
  }

  return NONE
}

const hasShortFlag = (words: readonly string[], letter: string) =>
  words.some(word => /^-[A-Za-z]+$/.test(word) && word.includes(letter))

// The deny rules: judged on the words of one command (quoted text is blank).
const denyOf = (words: readonly string[]): DenyRule | undefined => {
  const name = base(words[0])

  if (name === 'rm') {
    const isRecursive = hasShortFlag(words, 'r') || hasShortFlag(words, 'R') || hasFlag(words, '--recursive')
    const isForced = hasShortFlag(words, 'f') || hasFlag(words, '--force')

    return isRecursive && isForced ? 'rmrf' : undefined
  }
  if (name !== 'git') {
    return undefined
  }
  // Options before the subcommand: -C <dir>, -c <k=v>, and flags.
  let at = 1
  while (at < words.length && isFlag(words[at] as string)) {
    at += words[at] === '-C' || words[at] === '-c' ? 2 : 1
  }
  const sub = words[at]
  const args = words.slice(at + 1)

  if (sub === 'reset') {
    return 'reset'
  }
  if (sub === 'push') {
    return hasShortFlag(args, 'f') || hasFlag(args, '--force') || hasFlag(args, '--force-with-lease')
      ? 'force'
      : undefined
  }
  if (sub === 'clean') {
    return hasShortFlag(args, 'f') || hasFlag(args, '--force') ? 'clean' : undefined
  }
  if (sub === 'restore') {
    return args.includes('.') && !hasFlag(args, '--staged', '-S') ? 'clean' : undefined
  }
  if (sub === 'checkout') {
    const dashes = args.indexOf('--')

    return dashes >= 0 && args[dashes + 1] === '.' ? 'clean' : undefined
  }

  return undefined
}

// `docker compose ...` / `docker-compose ...`: the verb, the service, and the
// command run inside it, classified like any other.
const composeOf = (words: readonly string[]): Found => {
  const name = base(words[0])
  const after = name === 'docker' ? (words[1] === 'compose' ? words.slice(2) : undefined) : words.slice(1)
  if (after === undefined) {
    return NONE
  }
  const rest = after.slice(skipFlags(after, COMPOSE_GLOBAL))
  const verb = rest[0]
  const args = rest.slice(1)

  if (verb === 'exec' || verb === 'run') {
    const valued = verb === 'exec' ? EXEC_VALUED : RUN_VALUED
    const from = skipFlags(args, valued)
    const svc = args[from]
    const inner = commandOf(args.slice(from + 1))
    const found = inner.length > 0 ? toolOf(inner) : NONE
    const deny = inner.length > 0 ? denyOf(inner) : undefined
    const isRun = verb === 'run'

    return {
      ...(found.kind === 'test' || found.kind === 'lint' ? found : { kind: 'exec' as const }),
      ...(svc !== undefined ? { svc } : {}),
      ...(found.kind === 'none' ? { sub: verb } : {}),
      ...(isRun ? { rm: hasFlag(args.slice(0, from), '--rm') } : {}),
      ...(deny ? { deny } : {}),
    }
  }
  if (verb === 'up') {
    const from = skipFlags(args, UP_VALUED)
    const svc = args[from]

    return {
      kind: 'exec',
      sub: 'up',
      detached: hasFlag(args, '--detach', '-d') || hasShortFlag(args.slice(0, from), 'd'),
      ...(svc !== undefined ? { svc } : {}),
    }
  }
  if (verb === 'down') {
    return { kind: 'exec', sub: 'down', deny: 'down' }
  }

  return verb === undefined ? NONE : { kind: 'exec', sub: verb }
}

const classifyWords = (segment: string[]): Found => {
  const words = commandOf(segment)
  if (words.length === 0) {
    return NONE
  }
  const name = base(words[0])
  if (name === 'docker' || name === 'docker-compose') {
    return composeOf(words)
  }
  if (name === 'worktree') {
    return { kind: 'worktree', ...(words[1] ? { sub: words[1] } : {}) }
  }
  const found = toolOf(words)
  const deny = denyOf(words)

  return deny ? { ...found, deny } : found
}

// Every segment of a command, in order. A command that ends in `&` runs in the
// background, so none of its segments is the last.
export const classify = (command: string): Segment[] => {
  const segments = segmentsOf(command).filter(words => words.length > 0)
  const isBackground = /(?:^|[^&])&\s*$/.test(stripQuoted(command).trim())

  return segments.map((words, i) => ({
    ...classifyWords(words),
    isLast: i === segments.length - 1 && !isBackground,
  }))
}

// The segment a call's weather or weeding comes from: the last test or lint one.
export const workOf = (segments: readonly Segment[]): Segment | undefined =>
  [...segments].reverse().find(segment => segment.kind === 'test' || segment.kind === 'lint')

// The first deny rule any segment of the command matches.
export const denyRuleOf = (segments: readonly Segment[]): DenyRule | undefined =>
  segments.find(segment => segment.deny !== undefined)?.deny
