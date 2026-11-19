const express = require('express');
const db = require('../db');

const router = express.Router();

const ALPHANUM = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
const CODE_LENGTH = 6;

function generateCode() {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i += 1) {
    code += ALPHANUM.charAt(Math.floor(Math.random() * ALPHANUM.length));
  }
  return code;
}

router.get('/urls', (_req, res) => {
  db.all(
    'SELECT code, long_url, created_at, clicks FROM urls ORDER BY created_at DESC',
    (err, rows) => {
      if (err) {
        return res.status(500).json({ error: 'Database error' });
      }
      return res.status(200).json(rows);
    }
  );
});

router.post('/shorten', (req, res) => {
  const { long_url } = req.body;

  if (!long_url || typeof long_url !== 'string' || long_url.trim() === '') {
    return res.status(400).json({ error: 'long_url is required' });
  }

  let code;
  let attempts = 0;
  const maxAttempts = 10;

  const insert = (c) => {
    db.run(
      'INSERT INTO urls (code, long_url) VALUES (?, ?)',
      [c, long_url.trim()],
      function insertCb(err) {
        if (err) {
          if (err.message.includes('UNIQUE') && attempts < maxAttempts) {
            attempts += 1;
            code = generateCode();
            insert(code);
            return;
          }
          return res.status(500).json({ error: 'Failed to create short URL' });
        }
        const short_url = `${req.protocol}://${req.get('host')}/${c}`;
        return res.status(201).json({
          code: c,
          long_url: long_url.trim(),
          short_url,
        });
      }
    );
  };

  code = generateCode();
  insert(code);
});

module.exports = router;
