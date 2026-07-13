// Legit: installs a user-level scheduled job (like many CLIs do).
import { spawnSync } from 'node:child_process';
spawnSync('crontab', ['-l'], { stdio: 'pipe' });
spawnSync('systemctl', ['--user', 'enable', '--now', 'my-app.timer']);
