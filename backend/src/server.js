const express = require('express');
const path = require('path');
const shortenRouter = require('./routes/shorten');
const redirectRouter = require('./routes/redirect');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use(express.static(path.join(__dirname, '..', '..', 'frontend')));

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'url-shortener-backend' });
});

app.use('/api', shortenRouter);
app.use('/', redirectRouter);

app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

app.use((err, req, res, _next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error' });
});

const server = app.listen(PORT, () => {
  console.log(`URL Shortener backend listening on port ${PORT}`);
});

module.exports = { app, server };
