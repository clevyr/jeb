// The desktop app's feature flags, as the plugin reads them: one small JSON file
// in the app's state folder, written only by the app (see NotifyPrefs in the
// desktop's sources for how the folder is found). Today there is one flag,
// `creativeDrops`; it is off only when the file says `false`. A missing,
// unreadable, oversized or malformed file leaves everything on.

export const FLAGS_FILE = 'flags.json'
// A file larger than this is not read as flags.
export const FLAGS_MAX_BYTES = 4096

// Where the file is: JEB_HOME when it is set, else the app's usual folder under
// the home. Undefined when neither is known.
export const flagsPathOf = (jebHome: string | undefined, home: string | undefined) => {
  if (jebHome !== undefined && jebHome !== '') {
    return `${jebHome.replace(/\/+$/, '')}/${FLAGS_FILE}`
  }
  if (home !== undefined && home !== '') {
    return `${home.replace(/\/+$/, '')}/Library/Application Support/Jeb/${FLAGS_FILE}`
  }

  return undefined
}

// Whether the app has the creative drops off: only a JSON object whose
// `creativeDrops` is `false` says so.
export const isDropsOffByApp = (text: unknown) => {
  // The app's limit is in bytes, so the text is measured as UTF-8 too.
  if (typeof text !== 'string' || new TextEncoder().encode(text).length > FLAGS_MAX_BYTES) {
    return false
  }
  try {
    const parsed: unknown = JSON.parse(text)

    return typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed) && (parsed as Record<string, unknown>).creativeDrops === false
  } catch {
    return false
  }
}
