process.env.DB_PATH = ':memory:';
process.env.PORT = '0';

const request = require('supertest');
const { app, server } = require('../server');
const db = require('../db');

beforeAll((done) => {
  db.serialize(() => {
    db.run(
      `CREATE TABLE IF NOT EXISTS urls (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT UNIQUE NOT NULL,
        long_url TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        clicks INTEGER DEFAULT 0
      )`,
      done,
    );
  });
});

afterAll((done) => {
  server.close(() => {
    db.close(done);
  });
});

describe('GET /:code', () => {
  beforeEach((done) => {
    db.run('DELETE FROM urls', done);
  });

  it('should redirect 302 to the long URL for a valid short code', async () => {
    const longUrl = 'https://example.com/target-page';
    await new Promise((resolve, reject) => {
      db.run(
        'INSERT INTO urls (code, long_url, clicks) VALUES (?, ?, ?)',
        ['abc123', longUrl, 0],
        function (err) {
          if (err) return reject(err);
          resolve(this);
        },
      );
    });

    const res = await request(app).get('/abc123').redirects(0).expect(302);

    expect(res.headers.location).toBe(longUrl);
  });

  it('should increment click count on redirect', async () => {
    await new Promise((resolve, reject) => {
      db.run(
        'INSERT INTO urls (code, long_url, clicks) VALUES (?, ?, ?)',
        ['xyz789', 'https://example.com/clicks', 5],
        function (err) {
          if (err) return reject(err);
          resolve(this);
        },
      );
    });

    await request(app).get('/xyz789').redirects(0).expect(302);

    db.get('SELECT clicks FROM urls WHERE code = ?', ['xyz789'], (err, row) => {
      expect(err).toBeNull();
      expect(row.clicks).toBe(6);
    });
  });

  it('should return 404 for an unknown short code', async () => {
    const res = await request(app).get('/nonexistent').redirects(0).expect(404);

    expect(res.body.error).toBeDefined();
  });
});

describe('GET /health', () => {
  it('should return 200 with status ok', async () => {
    const res = await request(app).get('/health').expect('Content-Type', /json/).expect(200);

    expect(res.body.status).toBe('ok');
    expect(res.body.service).toBe('url-shortener-backend');
  });
});
