// Read-only reactions: what Jeb makes of a prompt (it is only read, never
// changed) and of the usage limits.

export type Reaction = { line?: string; wag?: boolean; wink?: boolean; puff?: boolean }

const SWEARS = /\b(?:damn|dammit|goddamn|hell|crap|shit|bullshit|wtf|fuck\w*)\b/
const THANKS = /\bthank(?:s| you)\b|\bthx\b/
const SHINE = /\b(?:moonshine|shine)\b/
const BLUE = /\bgood boy\b|\bblue\b/
const JEB = /\bjeb\b/
const DEPLOY = /\bdeploy(?:ing|ed|s|ment)?\b|\bship it\b/
const FRIDAY = /\bfriday\b/

export const reactTo = (text: string): Reaction => {
  const t = text.toLowerCase()
  const reaction: Reaction = {}

  if (DEPLOY.test(t)) {
    reaction.puff = true
    if (FRIDAY.test(t)) {
      reaction.line = 'Deployin\' on a Friday? Bless your heart.'
    } else {
      reaction.line = "Warmin' up the truck."
    }
  }
  if (SHINE.test(t)) {
    reaction.wink = true
  }
  if (BLUE.test(t)) {
    reaction.wag = true
  }
  if (!reaction.line) {
    if (SWEARS.test(t)) {
      reaction.line = "Language! Mamaw'd wash your mouth out with lye soap."
    } else if (THANKS.test(t)) {
      reaction.line = "Don't mention it."
    } else if (JEB.test(t)) {
      reaction.line = "That's my name, don't wear it out."
    }
  }

  return reaction
}

// Usage windows: 0 under 80 percent, 1 from 80, 2 from 95.
export const limitLevel = (percent: number) => (percent >= 95 ? 2 : percent >= 80 ? 1 : 0)

export const limitCrossings = (
  previous: Record<string, number>,
  limits: readonly { kind: string; percentUsed: number }[],
) => {
  const next: Record<string, number> = {}
  let isCrossed = false

  for (const limit of limits) {
    const level = limitLevel(limit.percentUsed)
    next[limit.kind] = level
    if (level > (previous[limit.kind] ?? 0)) {
      isCrossed = true
    }
  }

  return { next, isCrossed }
}

export const LIMIT_LINE = "Mash barrel's gettin' low, partner."





