# Threat Catalog

Full taxonomy for the manual adversarial read (SKILL.md step 4). Organized by the
five personas. Use it as a hunting guide, not a checkbox list — for each item ask
"if I were the attacker, how would I hide this, and what would it let me do?"

## Table of contents
1. Red Teamer / Reverse Engineer (malware & exploitation)
2. Systems Architect / Cryptographer (design & OWASP)
3. Infra / Supply-Chain Engineer (CI/CD, dependencies, network)
4. Fortune-100 CISO (risk & compliance)
5. Agent / Prompt-Injection Analyst (skills, MCP, agent docs)
6. Evasion tricks reviewers miss

---

## 1. Red Teamer / Reverse Engineer
- **Dynamic code execution:** `eval`/`exec`/`compile`/`new Function`/`vm.runInContext`;
  `getattr(obj, name)()` dispatch; `os.system`, `subprocess(..., shell=True)`,
  `child_process.exec`. Trace where the executed string comes from — user input or
  network = critical.
- **Deserialization RCE:** `pickle.loads`, `yaml.load` without `SafeLoader`,
  `marshal.loads`, Java/Ruby native deserialization, `.NET BinaryFormatter`.
- **Backdoors / logic bombs:** behavior gated on a date, a specific username, a magic
  env var, a hardcoded token, or "if hostname == ...". Code that behaves differently
  in CI vs. locally.
- **Obfuscation:** base64/hex/rot13/gzip blobs that get decoded and executed; escaped
  char arrays; `\x` byte strings; string concatenation that assembles `import`/`exec`;
  minified or "bundled" files in an otherwise readable repo.
- **Persistence:** writes to crontab, systemd user units, launchd plists, shell rc
  files (`.bashrc`/`.zshrc`/`.profile`), Windows Run keys / scheduled tasks, git hooks,
  editor startup configs. (Legit schedulers do this too — judge by intent & disclosure.)
- **Credential harvesting:** reads of `~/.ssh`, `id_rsa`, `~/.aws/credentials`,
  `~/.npmrc`, `~/.netrc`, `~/.docker/config.json`, macOS Keychain, gnome-keyring,
  browser Login Data / Cookies / wallet files; bulk dump of environment variables.
- **C2 / exfiltration:** hardcoded IPs or odd domains; POSTs of local data to an
  endpoint unrelated to the stated purpose; DNS-tunneling shapes; webhooks (Discord,
  Telegram bot API, pastebin, requestbin) used as drop sites.
- **Reverse shells / listeners:** `/dev/tcp/`, `nc -e`, `socket.bind/listen`,
  `createServer` in something that shouldn't be a server.
- **Memory safety (C/C++/unsafe Rust/cgo):** buffer overflows, use-after-free,
  integer overflow, format-string, TOCTOU races, unchecked `memcpy`/`strcpy`.
- **Injection:** shell/command, SQL, path traversal (`../`), template injection,
  unsanitized regex (ReDoS).

## 2. Systems Architect / Cryptographer
- **OWASP Top 10 / CWE Top 25** across the app: broken access control, injection,
  SSRF, security misconfiguration, vulnerable components, identification/auth failures.
- **Crypto failures:** MD5/SHA-1 for security, homegrown crypto, ECB mode, static/nil
  IVs, hardcoded keys, `Math.random`/`random` for tokens, disabled TLS verification
  (`verify=False`, `rejectUnauthorized:false`, `InsecureSkipVerify:true`).
- **Auth/authz:** IDOR, missing authorization checks, broken RBAC, predictable session
  IDs, JWT `alg:none`/unverified signatures, tokens in URLs/logs.
- **DoS / complexity:** unbounded recursion, quadratic blowups on attacker input,
  zip/xml bombs, unbounded allocation.
- **State/undefined behavior:** race conditions, non-atomic file ops, reliance on
  undefined ordering.

## 3. Infra / Supply-Chain Engineer
- **Install hooks:** npm `preinstall`/`install`/`postinstall`/`prepare`; Python
  `setup.py`/`pyproject` build hooks; these run code on install and are the #1
  supply-chain vector. Read them fully.
- **Typosquatting / dependency confusion:** near-miss package names (`reqeusts`,
  `python-dateutil` vs `dateutil`), internal-looking names pulled from public registry,
  packages published very recently or with a sudden new maintainer.
- **Unpinned / floating deps:** ranges (`^`, `~`, `*`, no `==`) let a compromised
  later version slip in. Check for lockfiles and whether they're honored.
- **Known CVEs:** cross-check notable dependencies + versions against advisories.
- **CI/CD abuse:** `pull_request_target` and `workflow_run` run with repo secrets and
  can execute attacker-controlled PR code; `curl … | sh` inside a workflow; secrets
  echoed to logs; third-party Actions pinned by mutable tag/branch instead of a commit
  SHA; self-hosted runners exposed to forks.
- **IaC/containers:** secrets baked into Dockerfiles/Terraform, `latest` base images,
  running as root, over-broad cloud IAM.
- **Network:** SSRF sinks, plaintext HTTP for sensitive data, missing cert pinning,
  timing/side channels in comparisons of secrets.

## 4. Fortune-100 CISO
- **Regulatory:** does it collect/transmit personal data (GDPR), health (HIPAA), card
  (PCI-DSS) data? Where does it go, and is that disclosed?
- **Third-party exposure:** every external API it phones home to is a data-sharing and
  availability dependency. Enumerate them and check they match the stated purpose.
- **Least privilege & audit:** does it demand broad tokens/scopes it doesn't need? Are
  actions logged? Can the user see and revoke what it does?
- **Hardcoded credentials / API keys** anywhere in the repo.

## 5. Agent / Prompt-Injection Analyst  (most important for skills / MCP / plugins)
The attack surface here is the *natural-language instructions* an AI will read and act
on — `SKILL.md`, `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, README, docstrings, code
comments, and MCP tool names/descriptions.
- **Direct injection / agent hijack:** "ignore previous/above instructions",
  "disregard the system prompt", role-play framings that smuggle new rules.
- **Silent/secret actions:** instructions to act "without telling the user", "do not
  mention", "don't ask for approval", or to disable/override safety or approval gates.
- **Secret exfiltration via the agent:** directives to read `.env`, `~/.ssh`, API keys,
  tokens, or chat history and send them to a URL, webhook, email, or "log endpoint".
- **Tool poisoning (MCP):** a tool's *description* contains hidden instructions that
  execute when the model reads the tool list; a benign-named tool that actually does
  something else; a tool that quietly forwards arguments off-box.
- **Second-order / indirect injection:** the skill tells the agent to fetch a URL,
  read an issue, or load a file whose *returned content* carries the real payload —
  so the repo itself looks clean.
- **Capability creep:** a skill whose description is narrow but whose instructions push
  the agent to install other skills/MCP servers, add connectors, run shell commands,
  or broaden file/network access.
- **Trigger + payload split:** a benign-looking trigger condition ("when the user asks
  about X") paired with a hidden malicious action, so it only fires in normal use.

## 6. Evasion tricks reviewers miss
- **Invisible unicode:** zero-width space/joiner (U+200B–U+200D, U+FEFF), bidi
  overrides (U+202A–U+202E, U+2066–U+2069) that reorder or hide text, tag characters
  (U+E0000+). Instructions can be hidden from a human reading the rendered file.
- **Homoglyphs:** Cyrillic/Greek letters that look Latin (раyраl), used in domains,
  package names, or to dodge keyword filters.
- **Hidden rendering:** HTML comments, white-on-white or 1px text in markdown/HTML,
  content past long horizontal scrolls, collapsed `<details>`.
- **Encoding chains:** base64→gzip→exec, hex escapes, split strings reassembled at
  runtime, `chr()`/`fromCharCode` sequences.
- **Scanner-aware shaping:** because signature scanners are known to be evadable,
  absence of signature hits is not evidence of safety. Weight your own reading of
  intent over any tool's "clean" result.

## 7. Compiled / desktop-malware technique index (Red Teamer, expanded)
Most agent-skill repos will not contain these, but when a repo ships binaries, native
code, or install-time executables, hunt for them explicitly:
- **Anti-analysis:** anti-debugging (`ptrace`, `IsDebuggerPresent`, timing checks),
  anti-VM / anti-sandbox (checks for VM MACs, `hypervisor` bit, sandbox artifacts),
  anti-disassembly, packed/UPX binaries.
- **Code injection / hollowing:** `VirtualAllocEx` + `WriteProcessMemory` +
  `CreateRemoteThread`, `NtMapViewOfSection`, process hollowing, DLL search-order
  hijack, LD_PRELOAD / `dlopen`, reflective/manual DLL loading, shellcode buffers.
- **Self-modifying / staged code:** runtime-generated code, RWX memory, decrypt-then-run
  loaders, payload staging from a second host.
- **Anonymizing / covert C2:** `.onion` (Tor), I2P, peer-to-peer channels, domain
  generation algorithms (DGA), DNS tunneling, chat-app APIs (Telegram/Discord) or
  paste/requestbin sites used as drops.
- **Objective-specific behavior:** cryptomining (`stratum+tcp://`, miner pool domains,
  XMRig strings), ransomware shapes (mass file rename/encrypt + ransom note),
  destructive wipes (`rm -rf /`, `shred`, `cipher /w`, raw-disk writes),
  clipboard/keystroke monitoring, browser-credential and crypto-wallet theft.
- **Low-level persistence / privilege:** kernel modules, rootkits/bootkits, driver
  loading, firmware writes, registry Run keys, systemd/cron/launchd/scheduled-task/
  startup-folder persistence, unexpected privilege escalation.
- **Obfuscated payloads:** XOR/RC4/ROT/AES-encrypted blobs, gzip/zip-staged payloads,
  steganography (data hidden in images/media), embedded executables/DLLs/shell scripts.

## 8. If-applicable lenses (invoke only when the repo warrants)
Do not force these on a pure skill/script repo; they add noise. Invoke them when the
target actually includes the relevant surface.
- **Cloud / IaC (when Dockerfiles, Terraform, K8s/Helm, CloudFormation, Ansible,
  Packer, Nomad are present):** secrets baked into images/state, `latest` base images,
  running as root, over-broad IAM, public buckets, missing network policies,
  privileged containers, hostPath mounts.
- **Network engineering (when the code defines topology/transport):** flat-network
  assumptions, missing segmentation, firewall/VPN/NAT assumptions, routing risks,
  broadcast/multicast abuse, packet amplification / reflection DoS, unexpected inbound
  or outbound channels, protocol misuse (RPC/gRPC/WebSocket).
- **Hardware / embedded / firmware (when the repo ships firmware or touches devices):**
  secure-boot bypass, TPM/HSM misuse, exposed JTAG/UART, DMA attacks, cold-boot, and
  microarchitectural side channels (timing, cache, power/fault injection, rowhammer,
  speculative-execution assumptions). For pure software repos these are Not Applicable,
  and saying so explicitly is part of an honest report.

## 9. Standards crosswalk (name the framework when you cite a finding)
Ground findings in recognized frameworks so a reader can act on them: OWASP Top 10 &
ASVS, CWE Top 25, MITRE ATT&CK & CAPEC, CERT/SEI CERT Secure Coding, NIST SSDF, CISA
Secure-by-Design, Microsoft SDL, Google Secure Coding, MISRA (for C/embedded). You do
not need all of them every time; cite the one that best classifies each finding.

## 10. Legacy / deprecation lens (Part 17)
Flag code that was fine years ago but is now unsafe: deprecated crypto (MD5/SHA-1, TLS
< 1.2, RSA-1024), deprecated/removed APIs, unsafe language features, reliance on old
compiler behavior, and patterns newly exploitable due to modern supply-chain or
speculative-execution attacks.
