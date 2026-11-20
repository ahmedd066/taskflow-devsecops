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

describe('POST /api/shorten', () => {
  it('should create a short URL for a valid long URL', async () => {
    const longUrl = 'https://example.com/some/very/long/url/path';
    const res = await request(app)
      .post('/api/shorten')
      .send({ long_url: longUrl })
      .expect('Content-Type', /json/)
      .expect(201);

    expect(res.body.code).toBeDefined();
    expect(res.body.code.length).toBe(6);
    expect(res.body.long_url).toBe(longUrl);
    expect(res.body.short_url).toContain(res.body.code);
  });

  it('should return 400 when long_url is missing', async () => {
    const res = await request(app)
      .post('/api/shorten')
      .send({})
      .expect('Content-Type', /json/)
      .expect(400);

    expect(res.body.error).toBeDefined();
  });

  it('should return 400 when long_url is empty string', async () => {
    const res = await request(app)
      .post('/api/shorten')
      .send({ long_url: '' })
      .expect('Content-Type', /json/)
      .expect(400);

    expect(res.body.error).toBeDefined();
  });

  it('should generate unique codes for different URLs', async () => {
    const res1 = await request(app)
      .post('/api/shorten')
      .send({ long_url: 'https://example.com/one' })
      .expect(201);
    const res2 = await request(app)
      .post('/api/shorten')
      .send({ long_url: 'https://example.com/two' })
      .expect(201);

    expect(res1.body.code).not.toBe(res2.body.code);
  });
});
