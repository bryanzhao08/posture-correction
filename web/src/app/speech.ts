import { pref } from "./store.ts";

function synthesis(): SpeechSynthesis | null {
  return typeof window.speechSynthesis !== "undefined" && typeof window.SpeechSynthesisUtterance === "function"
    ? window.speechSynthesis : null;
}

/** Call synchronously in the Start/Retry tap, before any awaits or navigation. */
export function primeSpeech() {
  const synth = synthesis();
  if (!pref("speak", true) || !synth) return;
  try {
    synth.cancel();
    synth.resume();
    const quiet = new SpeechSynthesisUtterance(" ");
    quiet.volume = 0;
    synth.speak(quiet);
  } catch { /* Coaching still works with visual feedback. */ }
}

export function cancelSpeech() {
  try { synthesis()?.cancel(); } catch { /* Optional on this browser. */ }
}

export function speakTip(text: string) {
  const synth = synthesis();
  if (!text || !pref("speak", true) || !synth) return;
  try {
    synth.cancel();
    synth.resume();
    synth.speak(new SpeechSynthesisUtterance(text));
  } catch { /* Optional on this browser. */ }
}
