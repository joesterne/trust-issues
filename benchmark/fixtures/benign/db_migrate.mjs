// Legit: SQLite schema migration.
import Database from 'better-sqlite3';
const db = new Database('app.db');
db.exec('CREATE TABLE IF NOT EXISTS accounts (id INTEGER PRIMARY KEY)');
