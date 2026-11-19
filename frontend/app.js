const form = document.getElementById('shortenForm');
const longUrlInput = document.getElementById('longUrl');
const submitBtn = document.getElementById('submitBtn');
const result = document.getElementById('result');
const shortUrlInput = document.getElementById('shortUrl');
const copyBtn = document.getElementById('copyBtn');
const status = document.getElementById('status');
const linksList = document.getElementById('linksList');

const API_BASE = window.location.origin;

function setLoading(loading) {
  submitBtn.disabled = loading;
  submitBtn.textContent = loading ? 'Shortening...' : 'Shorten';
}

function showStatus(message, type) {
  status.textContent = message;
  status.className = `status ${type}`;
  status.hidden = false;
}

function hideStatus() {
  status.hidden = true;
}

function showResult(shortUrl) {
  shortUrlInput.value = shortUrl;
  result.classList.remove('hidden');
  showStatus('Short URL created successfully.', 'success');
}

function addLinkToList(shortUrl, longUrl) {
  const empty = linksList.querySelector('.empty');
  if (empty) {
    empty.remove();
  }

  const li = document.createElement('li');
  const shortLink = document.createElement('a');
  shortLink.href = shortUrl;
  shortLink.textContent = shortUrl;
  shortLink.target = '_blank';
  shortLink.rel = 'noopener noreferrer';

  const longText = document.createElement('span');
  longText.textContent = `\u2192 ${longUrl}`;
  longText.style.color = '#64748b';
  longText.style.fontSize = '0.875rem';
  longText.style.marginLeft = '8px';

  li.appendChild(shortLink);
  li.appendChild(longText);
  linksList.prepend(li);
}

async function shortenUrl(longUrl) {
  const response = await fetch(`${API_BASE}/api/shorten`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ long_url: longUrl }),
  });

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    throw new Error(errorData.error || 'Failed to shorten URL');
  }

  return await response.json();
}

async function copyToClipboard(text) {
  try {
    await navigator.clipboard.writeText(text);
    showStatus('Copied to clipboard!', 'success');
    setTimeout(hideStatus, 2000);
  } catch (err) {
    shortUrlInput.select();
    document.execCommand('copy');
    showStatus('Copied to clipboard!', 'success');
    setTimeout(hideStatus, 2000);
  }
}

async function loadLinks() {
  try {
    const response = await fetch(`${API_BASE}/api/urls`);
    if (!response.ok) {
      return;
    }
    const links = await response.json();
    links.forEach(({ code, long_url }) => {
      const short_url = `${API_BASE}/${code}`;
      addLinkToList(short_url, long_url);
    });
  } catch (err) {
    // ignore load failures
  }
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  hideStatus();

  const longUrl = longUrlInput.value.trim();
  if (!longUrl) {
    showStatus('Please enter a valid URL.', 'error');
    return;
  }

  setLoading(true);

  try {
    const data = await shortenUrl(longUrl);
    showResult(data.short_url);
    addLinkToList(data.short_url, data.long_url);
    longUrlInput.value = '';
  } catch (err) {
    showStatus(err.message || 'Something went wrong. Please try again.', 'error');
  } finally {
    setLoading(false);
  }
});

copyBtn.addEventListener('click', () => {
  const text = shortUrlInput.value;
  if (text) {
    copyToClipboard(text);
  }
});

shortUrlInput.addEventListener('click', () => {
  shortUrlInput.select();
});

loadLinks();
