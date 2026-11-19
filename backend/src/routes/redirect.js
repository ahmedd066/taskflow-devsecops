const express = require('express');
const db = require('../db');

const router = express.Router();

router.get('/:code', (req, res) => {
  const { code } = req.params;

  if (!code || code.trim() === '') {
    return res.status(404).json({ error: 'Short code not found' });
  }

  db.get(
    'SELECT long_url FROM urls WHERE code = ?',
    [code.trim()],
    (err, row) => {
      if (err) {
        return res.status(500).json({ error: 'Database error' });
      }
      if (!row) {
        return res.status(404).json({ error: 'Short code not found' });
      }

      db.run(
        'UPDATE urls SET clicks = clicks + 1 WHERE code = ?',
        [code.trim()],
        () => {}
      );

      return res.redirect(302, row.long_url);
    }
  );
});

module.exports = router;
