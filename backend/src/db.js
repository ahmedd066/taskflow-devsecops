const path = require('path');
const fs = require('fs');
const Database = require('sqlite3').Database;

const dbPath = process.env.DB_PATH || path.join(__dirname, '..', 'data', 'urls.db');

fs.mkdirSync(path.dirname(dbPath), { recursive: true });

const db = new Database(dbPath, (err) => {
  if (err) {
    console.error('Failed to open database:', err.message);
  }
});

db.serialize(() => {
  db.run(
    `CREATE TABLE IF NOT EXISTS urls (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      code TEXT UNIQUE NOT NULL,
      long_url TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      clicks INTEGER DEFAULT 0
    )`,
    (err) => {
      if (err) {
        console.error('Failed to create table:', err.message);
      }
    },
  );
});

module.exports = db;
