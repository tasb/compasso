// Crawl a public prototype by following same-origin links only: no clicks on buttons, no
// form submits, and no links that look destructive. Run by bin/prototype.sh crawl.
//   node prototype-crawl.mjs <start URL> <max pages> <out dir>  ->  <out>/raw.json, <out>/screens/<n>.png
import { chromium } from 'playwright';
import { writeFileSync, mkdirSync } from 'node:fs';

const [start, maxArg, out] = process.argv.slice(2);
const max = Number(maxArg) || 40;
const origin = new URL(start).origin;
const risky = /log-?out|sign-?out|delete|remove|destroy|unsubscribe/i;

// the page address without its fragment, except hash routes (#/cart) that single-page apps use
const norm = (href) => {
  const u = new URL(href, start);
  if (!u.hash.startsWith('#/')) u.hash = '';
  return u.href;
};

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
const queue = [norm(start)];
const seen = new Set(queue);
const pages = [];
mkdirSync(`${out}/screens`, { recursive: true });

while (queue.length > 0 && pages.length < max) {
  const url = queue.shift();
  const page = await context.newPage();
  try {
    await page.goto(url, { waitUntil: 'networkidle', timeout: 20000 });
    if (new URL(page.url()).origin !== origin) { pages.push({ url, error: `left the prototype for ${page.url()}` }); continue; }
    const data = await page.evaluate(() => {
      const text = (el) => (el.innerText || el.value || el.getAttribute('aria-label') || '').trim().replace(/\s+/g, ' ');
      const label = (el) => {
        if (el.id) { const l = document.querySelector(`label[for="${CSS.escape(el.id)}"]`); if (l) return text(l); }
        const wrap = el.closest('label'); if (wrap) return text(wrap);
        return el.getAttribute('aria-label') || el.getAttribute('placeholder') || '';
      };
      const field = (el) => ({ label: label(el), name: el.name || '', type: el.type || el.tagName.toLowerCase(), required: el.required });
      const fieldsIn = (root) => [...root.querySelectorAll('input, select, textarea')]
        .filter((el) => el.type !== 'hidden' && el.type !== 'submit' && el.type !== 'button').map(field);
      const forms = [...document.querySelectorAll('form')].map((f) => ({
        name: f.getAttribute('aria-label') || f.getAttribute('name') || f.id || '',
        fields: fieldsIn(f),
        submit: text(f.querySelector('button[type=submit], input[type=submit], button:not([type])') || document.createElement('i')),
      }));
      const loose = [...document.querySelectorAll('input, select, textarea')].filter((el) => !el.closest('form') && el.type !== 'hidden').map(field);
      if (loose.length > 0) forms.push({ name: '(fields outside a form)', fields: loose, submit: '' });
      return {
        title: document.title,
        headings: [...document.querySelectorAll('h1, h2, h3')].map(text).filter(Boolean).slice(0, 20),
        text: (document.body.innerText || '').replace(/\s+/g, ' ').slice(0, 2000),
        links: [...document.querySelectorAll('a[href]')].map((a) => ({ text: text(a), href: a.href })),
        buttons: [...document.querySelectorAll('button, [role=button], input[type=submit], input[type=button]')].map(text).slice(0, 40),
        forms,
      };
    });
    const n = pages.length + 1;
    await page.screenshot({ path: `${out}/screens/${n}.png`, fullPage: true });
    const links = [];
    for (const l of data.links) {
      let href;
      try { href = norm(l.href); } catch { continue; }
      if (new URL(href).origin !== origin || risky.test(href) || risky.test(l.text)) continue;
      links.push({ text: l.text, href });
      if (!seen.has(href)) { seen.add(href); queue.push(href); }
    }
    pages.push({ url, ...data, links, screenshot: `screens/${n}.png` });
  } catch (e) {
    pages.push({ url, error: String(e.message || e).split('\n')[0] });
  } finally {
    await page.close();
  }
}
await browser.close();
writeFileSync(`${out}/raw.json`, JSON.stringify(pages, null, 2));
