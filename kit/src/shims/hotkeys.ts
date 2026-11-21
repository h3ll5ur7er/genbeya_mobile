/**
 * Stands in for Genbeya's client/app/core/hotkeys.ts in the kit's bundle: the
 * editor modules need only these two constants from it, and the rest of that
 * module is an Angular service. Same values as Genbeya's.
 */
export const isMac = typeof navigator !== "undefined" && /Mac|iPhone|iPad/.test(navigator.platform);
export const MOD_KEY = isMac ? "⌘" : "Ctrl";
