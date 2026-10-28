import { abbrevCount } from './shared'
import { plural } from './util'

// Jeb's lines for what the session itself does: compaction, /clear, resume,
// a fork and a settings hook that says no. Pure.

export const SWEEP_LINE = "Sweepin' out the barn…"
export const SWEEP_AUTO_LINE = 'Barn got full, had to sweep.'
export const CLEAR_LINE = 'Fresh start. Same holler.'
export const FORK_LINE = 'Somebody split the firewood.'
export const GATE_LINE = 'Somebody put up a gate.'
export const FAR_PIECE_LINE = "Been a far piece. Crops kept growin'."

// "Swept the barn out: 140k down to 22k."; nothing when the engine did not say.
export const sweptLine = (before: number | undefined, after: number | undefined) =>
  before === undefined || after === undefined
    ? undefined
    : `Swept the barn out: ${abbrevCount(before)} down to ${abbrevCount(after)}.`

// "Back already? Been 12 minutes." up to a day, then the far piece.
export const resumeLine = (seconds: number | undefined) => {
  if (seconds === undefined || !Number.isFinite(seconds) || seconds < 0) {
    return 'Back already?'
  }
  if (seconds >= 86_400) {
    return FAR_PIECE_LINE
  }
  const minutes = Math.round(seconds / 60)
  const span =
    minutes < 1
      ? 'a spell'
      : minutes < 60
        ? plural(minutes, 'minute')
        : plural(Math.round(minutes / 60), 'hour')

  return `Back already? Been ${span}.`
}

export const CHORE_LINES = [
  SWEEP_LINE,
  SWEEP_AUTO_LINE,
  CLEAR_LINE,
  FORK_LINE,
  GATE_LINE,
  FAR_PIECE_LINE,
  sweptLine(140_000, 22_000) as string,
  resumeLine(90),
  resumeLine(7200),
]

// A settings hook's gate, kept by the id of the call it refused, so the call it
// belongs to is the one that is seen as refused and no other. At most MAX_GATES
// are kept (the oldest forgotten); a call with no id shares the one empty key.
export const MAX_GATES = 16

export const markGate = (gates: Map<string, true>, id: string | undefined) => {
  const key = id ?? ''
  gates.delete(key)
  gates.set(key, true)
  if (gates.size > MAX_GATES) {
    gates.delete(gates.keys().next().value as string)
  }
}

// Whether this call was refused; the gate is used up.
export const takeGate = (gates: Map<string, true>, id: string | undefined) => gates.delete(id ?? '')
