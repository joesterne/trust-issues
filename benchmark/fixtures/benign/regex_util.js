// Legit: the word 'exec' here is a regex method, not code execution.
export const parse = s => /^(\d+)([dwm])$/i.exec(s.trim());
