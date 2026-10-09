'use strict';
const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const jwt = require('jsonwebtoken');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { promisify } = require('node:util');
const scrypt = promisify(crypto.scrypt);
const nodemailer = require('nodemailer');

const app = express();
app.use(helmet());
app.use(express.json({ limit: '32kb' }));
app.use(rateLimit({ windowMs: 60_000, limit: 100, standardHeaders: true, legacyHeaders: false }));
const authLimiter = rateLimit({ windowMs: 15 * 60_000, limit: 10, standardHeaders: true, legacyHeaders: false, message: {error:'Too many authentication attempts. Wait 15 minutes and try again.'} });
const PORT = Number(process.env.PORT || 8080);
const JWT_SECRET = process.env.JWT_SECRET || '';
const OWNER_DISCORD_ID = process.env.OWNER_DISCORD_ID || '985486854159753256';
const OWNER_USERNAME = process.env.OWNER_USERNAME || 'InSaNe';
const OWNER_EMAIL = (process.env.OWNER_EMAIL || 'hydraabhinav121@gmail.com').toLowerCase();
const OWNER_INITIAL_PASSWORD = process.env.OWNER_INITIAL_PASSWORD || '';
const SMTP_HOST = process.env.SMTP_HOST || '';
const SMTP_PORT = Number(process.env.SMTP_PORT || 587);
const SMTP_USER = process.env.SMTP_USER || '';
const SMTP_PASS = process.env.SMTP_PASS || '';
const SMTP_FROM = process.env.SMTP_FROM || SMTP_USER;
const mailer = SMTP_HOST && SMTP_USER && SMTP_PASS ? nodemailer.createTransport({host: SMTP_HOST, port: SMTP_PORT, secure: SMTP_PORT === 465, auth: {user: SMTP_USER, pass: SMTP_PASS}}) : null;
const CLIENT_ID = process.env.DISCORD_CLIENT_ID || '';
const CLIENT_SECRET = process.env.DISCORD_CLIENT_SECRET || '';
const REDIRECT_URI = process.env.DISCORD_REDIRECT_URI || '';
const APP_REDIRECT_URI = process.env.APP_REDIRECT_URI || 'insanestraps://oauth/discord';
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, 'data');
const DATA_FILE = path.join(DATA_DIR, 'db.json');
const oauthStates = new Map();
const exchangeTickets = new Map();
if (!JWT_SECRET || !OWNER_DISCORD_ID) console.warn('WARNING: set JWT_SECRET and OWNER_DISCORD_ID before deployment. Owner-only endpoints will reject requests until configured.');
fs.mkdirSync(DATA_DIR, { recursive: true });
function initialDb() { return { prices: { day: 20, month: 120, lifetime: 500 }, payments: [], users: {}, accounts: {}, entitlements: {}, keys: [], resetRequests: {} }; }
function readDb() { try { return { ...initialDb(), ...JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')) }; } catch { return initialDb(); } }
function writeDb(db) { const tmp = DATA_FILE + '.tmp'; fs.writeFileSync(tmp, JSON.stringify(db, null, 2), { mode: 0o600 }); fs.renameSync(tmp, DATA_FILE); }
function admin(req, res, next) { try { const h = req.get('authorization') || ''; if (!h.startsWith('Bearer ') || !JWT_SECRET) throw new Error('missing'); const token = jwt.verify(h.slice(7), JWT_SECRET, { issuer: 'insane-straps-api' }); if (!(token.role === 'owner' || (OWNER_DISCORD_ID && token.sub === OWNER_DISCORD_ID))) return res.status(403).json({ error: 'Owner access only' }); req.user = token; next(); } catch { return res.status(401).json({ error: 'Sign in with the authorized owner account' }); } }
function auth(req, res, next) { try { const h = req.get('authorization') || ''; if (!h.startsWith('Bearer ') || !JWT_SECRET) throw new Error('missing'); req.user = jwt.verify(h.slice(7), JWT_SECRET, { issuer: 'insane-straps-api' }); next(); } catch { res.status(401).json({ error: 'Please sign in again' }); } }
function publicUser(u) { return { discordId: u.discordId, username: u.username, globalName: u.globalName || null, avatar: u.avatar || null }; }


const codeHash = code => crypto.createHash('sha256').update(String(code)).digest('hex');
const normalizeEmail = email => String(email || '').trim().toLowerCase();
const normalizeUsername = name => String(name || '').trim();
const validEmail = email => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
async function hashPassword(password) { const salt = crypto.randomBytes(16).toString('hex'); const derived = await scrypt(password, salt, 64); return `scrypt$${salt}$${derived.toString('hex')}`; }
async function verifyPassword(password, encoded) { try { const [, salt, hash] = String(encoded).split('$'); const actual = await scrypt(password, salt, 64); return crypto.timingSafeEqual(actual, Buffer.from(hash, 'hex')); } catch { return false; } }
function makeCode() { return String(crypto.randomInt(0, 1000000)).padStart(6, '0'); }
async function sendCode(email, code, purpose) {
  if (!mailer || !SMTP_FROM) throw new Error('Email delivery is not configured. Configure SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS and SMTP_FROM.');
  await mailer.sendMail({from: SMTP_FROM, to: email, subject: `Insane Straps ${purpose} code`, text: `Your Insane Straps ${purpose.toLowerCase()} code is ${code}. It expires in 10 minutes. If you did not request this, ignore this email. Do not share this code.`, html: `<div style="font-family:Arial;background:#09090d;color:#fff;padding:24px"><h2 style="color:#ff3048">INSANE STRAPS</h2><p>Your ${purpose.toLowerCase()} code is:</p><div style="font-size:30px;font-weight:bold;letter-spacing:8px">${code}</div><p>This code expires in 10 minutes. Do not share it.</p></div>`});
}
function accountToken(account) { return jwt.sign({sub: account.id, scope: 'user', role: account.role || 'user', kind: 'account'}, JWT_SECRET, {expiresIn: '30d', issuer: 'insane-straps-api'}); }
async function ensureOwnerAccount() {
  if (!OWNER_INITIAL_PASSWORD) { console.warn('OWNER_INITIAL_PASSWORD is unset; owner account provisioning is disabled until configured.'); return; }
  if (OWNER_INITIAL_PASSWORD.length < 12) { console.warn('OWNER_INITIAL_PASSWORD must be at least 12 characters; owner provisioning skipped.'); return; }
  const db = readDb(); db.accounts ||= {};
  const existing = Object.values(db.accounts).find(a => a.username.toLowerCase() === OWNER_USERNAME.toLowerCase() || a.email === OWNER_EMAIL);
  if (existing && !(existing.username.toLowerCase() === OWNER_USERNAME.toLowerCase() && existing.email === OWNER_EMAIL)) { console.error('Owner bootstrap conflict: username/email is already claimed by a different account. Resolve this manually before enabling owner access.'); return; }
  let created = false; let account = existing;
  if (!account) { const id = `owner_${crypto.randomBytes(12).toString('hex')}`; account = db.accounts[id] = {id, username: OWNER_USERNAME, email: OWNER_EMAIL, passwordHash: await hashPassword(OWNER_INITIAL_PASSWORD), emailVerified: false, role: 'owner', createdAt: new Date().toISOString(), profile: {displayName: OWNER_USERNAME, bio: ''}}; created = true; }
  if (account.role !== 'owner') account.role = 'owner';
  if (!account.emailVerified && mailer && (!account.verification || account.verification.expiresAt < Date.now())) { const code = makeCode(); account.verification = {hash: codeHash(code), expiresAt: Date.now()+10*60_000, attempts: 0}; writeDb(db); try { await sendCode(account.email, code, 'Owner email verification'); console.log(`Owner verification code sent to configured owner email.`); } catch(e) { console.error('Owner verification email failed:', e.message); } }
  else writeDb(db);
  if (created) console.log(`Provisioned owner account ${OWNER_USERNAME}; email verification required before first login.`);
}

function grantEntitlement(db, discordId, planId) {
  const now = Date.now(); const old = db.entitlements[discordId];
  const start = old && old.status === 'active' && old.expiresAt && Date.parse(old.expiresAt) > now ? Date.parse(old.expiresAt) : now;
  db.entitlements[discordId] = planId === 'lifetime'
    ? { planId, status: 'active', activatedAt: new Date(now).toISOString(), expiresAt: null }
    : { planId, status: 'active', activatedAt: new Date(now).toISOString(), expiresAt: new Date(start + (planId === 'day' ? 24 : 24 * 30) * 60 * 60 * 1000).toISOString() };
  return db.entitlements[discordId];
}
function keyHash(key) { return crypto.createHash('sha256').update(key.trim().toUpperCase()).digest('hex'); }


app.post('/auth/register', authLimiter, async (req, res) => {
  try {
    const username = normalizeUsername(req.body?.username), email = normalizeEmail(req.body?.email), password = String(req.body?.password || '');
    if (!/^[A-Za-z0-9_]{3,24}$/.test(username) || !validEmail(email) || password.length < 10 || password.length > 128) return res.status(400).json({error:'Use a 3–24 character username, valid email, and password of at least 10 characters.'});
    const db = readDb(); db.accounts ||= {};
    if (Object.values(db.accounts).some(a => a.username.toLowerCase() === username.toLowerCase() || a.email === email)) return res.status(409).json({error:'Username or email is already registered.'});
    if (!mailer) return res.status(503).json({error:'Email verification is not configured yet. Please try again later.'});
    const id = `user_${crypto.randomBytes(12).toString('hex')}`; const code = makeCode();
    db.accounts[id] = {id, username, email, passwordHash: await hashPassword(password), emailVerified:false, role:'user', createdAt:new Date().toISOString(), profile:{displayName:username,bio:''}, verification:{hash:codeHash(code),expiresAt:Date.now()+10*60_000,attempts:0}};
    writeDb(db); await sendCode(email, code, 'Email verification'); res.status(201).json({ok:true,verificationRequired:true,message:'Verification code sent to your email.'});
  } catch(e) { console.error('Registration failed:', e.message); res.status(503).json({error:e.message.includes('Email delivery')?e.message:'Could not complete registration. Try again later.'}); }
});
app.post('/auth/verify-email', authLimiter, async (req,res) => {
  const email=normalizeEmail(req.body?.email), code=String(req.body?.code||''); const db=readDb(); const account=Object.values(db.accounts||{}).find(a=>a.email===email);
  if (!account || account.emailVerified || !account.verification || account.verification.expiresAt<Date.now() || account.verification.attempts>=5) return res.status(400).json({error:'Code expired or invalid. Request a new code.'});
  account.verification.attempts++; if (account.verification.hash!==codeHash(code)) { writeDb(db); return res.status(400).json({error:'Incorrect verification code.'}); }
  account.emailVerified=true; delete account.verification; writeDb(db); res.json({ok:true,message:'Email verified. You can now sign in.'});
});
app.post('/auth/resend-verification', authLimiter, async (req,res) => {
  try { const email=normalizeEmail(req.body?.email); const db=readDb(); const account=Object.values(db.accounts||{}).find(a=>a.email===email); if (!account || account.emailVerified) return res.json({ok:true,message:'If the account needs verification, a code will be sent.'}); const code=makeCode(); account.verification={hash:codeHash(code),expiresAt:Date.now()+10*60_000,attempts:0}; writeDb(db); await sendCode(email,code,'Email verification'); res.json({ok:true,message:'A new code has been sent.'}); }
  catch(e){res.status(503).json({error:e.message.includes('Email delivery')?e.message:'Could not send code.'});}
});
app.post('/auth/login', authLimiter, async (req,res) => {
  const login=String(req.body?.login||'').trim().toLowerCase(), password=String(req.body?.password||''); const db=readDb(); const account=Object.values(db.accounts||{}).find(a=>a.username.toLowerCase()===login||a.email===login);
  if (!account || !(await verifyPassword(password,account.passwordHash))) return res.status(401).json({error:'Incorrect username/email or password.'});
  if (!account.emailVerified) return res.status(403).json({error:'Verify your email before logging in.',verificationRequired:true,email:account.email});
  const token=accountToken(account); res.json({token,user:{id:account.id,username:account.username,email:account.email,role:account.role,profile:account.profile}});
});
app.post('/auth/forgot-password', authLimiter, async (req,res) => {
  try { const email=normalizeEmail(req.body?.email); const db=readDb(); const account=Object.values(db.accounts||{}).find(a=>a.email===email); if (account && account.emailVerified) { const code=makeCode(); db.resetRequests ||= {}; db.resetRequests[account.id]={hash:codeHash(code),expiresAt:Date.now()+10*60_000,attempts:0}; writeDb(db); await sendCode(email,code,'Password reset'); } res.json({ok:true,message:'If a verified account exists for this email, a reset code has been sent.'}); }
  catch(e){res.status(503).json({error:e.message.includes('Email delivery')?e.message:'Could not send reset code.'});}
});
app.post('/auth/reset-password', authLimiter, async (req,res) => {
  const email=normalizeEmail(req.body?.email), code=String(req.body?.code||''), password=String(req.body?.newPassword||''); if(password.length<10||password.length>128) return res.status(400).json({error:'New password must be at least 10 characters.'});
  const db=readDb(); const account=Object.values(db.accounts||{}).find(a=>a.email===email); const reset=account && db.resetRequests?.[account.id]; if(!account||!reset||reset.expiresAt<Date.now()||reset.attempts>=5) return res.status(400).json({error:'Reset code expired or invalid. Request another code.'});
  reset.attempts++; if(reset.hash!==codeHash(code)){writeDb(db);return res.status(400).json({error:'Incorrect reset code.'});} account.passwordHash=await hashPassword(password); delete db.resetRequests[account.id]; writeDb(db); res.json({ok:true,message:'Password reset. You can now sign in.'});
});

app.get('/health', (_req, res) => res.json({ ok: true, service: 'Insane Straps API', emailDeliveryConfigured: Boolean(mailer), persistentDataDirectoryConfigured: Boolean(process.env.DATA_DIR), ownerBootstrapConfigured: Boolean(OWNER_INITIAL_PASSWORD && JWT_SECRET) }));
app.get('/config/prices', (_req, res) => res.json(readDb().prices));
app.get('/auth/discord/start', (req, res) => {
  if (!CLIENT_ID || !CLIENT_SECRET || !REDIRECT_URI || !JWT_SECRET) return res.status(503).send('Discord OAuth is not configured on the Insane Straps backend.');
  const state = crypto.randomBytes(24).toString('hex'); oauthStates.set(state, Date.now());
  for (const [key, time] of oauthStates) if (Date.now() - time > 10 * 60_000) oauthStates.delete(key);
  const u = new URL('https://discord.com/oauth2/authorize'); u.searchParams.set('client_id', CLIENT_ID); u.searchParams.set('redirect_uri', REDIRECT_URI); u.searchParams.set('response_type', 'code'); u.searchParams.set('scope', 'identify'); u.searchParams.set('state', state); res.redirect(u.toString());
});
app.get('/auth/discord/callback', async (req, res) => {
  const { code, state, error } = req.query;
  if (error || typeof code !== 'string' || typeof state !== 'string' || !oauthStates.has(state)) return res.status(400).send('Discord authorization failed. Return to Insane Straps and try again.');
  oauthStates.delete(state);
  try {
    const form = new URLSearchParams({ client_id: CLIENT_ID, client_secret: CLIENT_SECRET, grant_type: 'authorization_code', code, redirect_uri: REDIRECT_URI });
    const tokenRes = await fetch('https://discord.com/api/oauth2/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: form });
    if (!tokenRes.ok) throw new Error('Token exchange failed'); const tokenData = await tokenRes.json();
    const meRes = await fetch('https://discord.com/api/users/@me', { headers: { Authorization: `Bearer ${tokenData.access_token}` } });
    if (!meRes.ok) throw new Error('Discord identity lookup failed'); const me = await meRes.json();
    const db = readDb(); db.users[me.id] = { discordId: me.id, username: me.username, globalName: me.global_name || null, avatar: me.avatar || null, linkedAt: new Date().toISOString() }; writeDb(db);
    const ticket = crypto.randomBytes(32).toString('hex'); exchangeTickets.set(ticket, { discordId: me.id, expiresAt: Date.now() + 90_000 });
    res.redirect(`${APP_REDIRECT_URI}?ticket=${encodeURIComponent(ticket)}`);
  } catch (e) { console.error('Discord OAuth callback failed:', e.message); res.status(502).send('Could not finish Discord sign-in. Return to the app and retry.'); }
});
app.post('/auth/discord/exchange', (req, res) => {
  const ticket = req.body && req.body.ticket; const entry = typeof ticket === 'string' ? exchangeTickets.get(ticket) : null;
  if (!entry || entry.expiresAt < Date.now()) { if (ticket) exchangeTickets.delete(ticket); return res.status(401).json({ error: 'Expired or invalid sign-in ticket' }); }
  exchangeTickets.delete(ticket); const db = readDb(); const user = db.users[entry.discordId];
  const token = jwt.sign({ sub: user.discordId, scope: 'user' }, JWT_SECRET, { expiresIn: '30d', issuer: 'insane-straps-api' });
  res.json({ token, user: publicUser(user) });
});
app.get('/me', auth, (req, res) => { const db = readDb(); const account = db.accounts?.[req.user.sub]; const user = db.users[req.user.sub]; if (!account && !user) return res.status(404).json({ error: 'User not found' }); let entitlement = db.entitlements[req.user.sub] || { planId: 'free', status: 'free' }; if (entitlement.expiresAt && Date.parse(entitlement.expiresAt) <= Date.now()) entitlement = { planId: 'free', status: 'expired', expiresAt: entitlement.expiresAt }; res.json({ user: account ? {id:account.id, username:account.username, email:account.email, role:account.role, profile:account.profile, emailVerified:account.emailVerified} : publicUser(user), role: account?.role || (req.user.sub === OWNER_DISCORD_ID ? 'owner' : 'user'), entitlement }); });
app.post('/payments', auth, (req, res) => {
  const { planId, amount, transactionRef } = req.body || {}; const db = readDb();
  if (!['day', 'month', 'lifetime'].includes(planId) || !Number.isInteger(amount) || amount !== db.prices[planId] || typeof transactionRef !== 'string' || transactionRef.trim().length < 6 || transactionRef.trim().length > 128) return res.status(400).json({ error: 'Invalid plan, amount or transaction reference' });
  if (db.payments.some(p => p.transactionRef.toLowerCase() === transactionRef.trim().toLowerCase())) return res.status(409).json({ error: 'Transaction reference already submitted' });
  const payment = { id: crypto.randomUUID(), discordId: req.user.sub, planId, amount, transactionRef: transactionRef.trim(), status: 'pending', createdAt: new Date().toISOString(), reviewedAt: null };
  db.payments.push(payment); writeDb(db); res.status(201).json({ id: payment.id, status: payment.status });
});
app.get('/payments/mine', auth, (req, res) => { const db = readDb(); res.json(db.payments.filter(p => p.discordId === req.user.sub).map(({ id, planId, amount, transactionRef, status, createdAt, reviewedAt }) => ({ id, planId, amount, transactionRef, status, createdAt, reviewedAt }))); });
app.get('/admin/payments', admin, (_req, res) => { const db = readDb(); res.json(db.payments.map(p => ({ ...p, user: publicUser(db.users[p.discordId] || { discordId: p.discordId, username: 'Unknown' }) }))); });
app.post('/admin/payments/:id/review', admin, (req, res) => {
  const { status } = req.body || {}; if (!['approved', 'rejected'].includes(status)) return res.status(400).json({ error: 'Status must be approved or rejected' });
  const db = readDb(); const payment = db.payments.find(p => p.id === req.params.id); if (!payment) return res.status(404).json({ error: 'Payment not found' }); if (payment.status !== 'pending') return res.status(409).json({ error: 'Payment already reviewed' });
  payment.status = status; payment.reviewedAt = new Date().toISOString();
  if (status === 'approved') grantEntitlement(db, payment.discordId, payment.planId);
  writeDb(db); res.json({ ok: true, payment: { id: payment.id, status: payment.status } });
});
app.put('/admin/prices', admin, (req, res) => { const { day, month, lifetime } = req.body || {}; if (![day, month, lifetime].every(v => Number.isInteger(v) && v > 0 && v <= 1000000)) return res.status(400).json({ error: 'Prices must be positive integer rupee amounts' }); const db = readDb(); db.prices = { day, month, lifetime }; writeDb(db); res.json(db.prices); });
// Owner generates keys. Plaintext is returned only at creation; only SHA-256 hashes are stored.
app.post('/admin/keys', admin, (req, res) => {
  const { planId, quantity = 1, uses = 1 } = req.body || {};
  if (!['day', 'month', 'lifetime'].includes(planId) || !Number.isInteger(quantity) || quantity < 1 || quantity > 50 || !Number.isInteger(uses) || uses < 1 || uses > 500) return res.status(400).json({ error: 'Invalid plan, quantity or uses' });
  const db = readDb(); db.keys ||= []; const generated = [];
  for (let i = 0; i < quantity; i++) {
    let code, hash; do { code = 'IS-' + crypto.randomBytes(12).toString('hex').toUpperCase().match(/.{1,4}/g).join('-'); hash = keyHash(code); } while (db.keys.some(k => k.hash === hash));
    db.keys.push({ hash, planId, maxUses: uses, uses: 0, createdAt: new Date().toISOString(), revoked: false, redemptions: [] }); generated.push(code);
  }
  writeDb(db); res.status(201).json({ keys: generated, planId, maxUses: uses, warning: 'Copy these keys now; plaintext is not stored and will not be shown again.' });
});
app.get('/admin/keys', admin, (_req, res) => { const db = readDb(); res.json((db.keys || []).map(k => ({ planId: k.planId, maxUses: k.maxUses, uses: k.uses, createdAt: k.createdAt, revoked: k.revoked, hashSuffix: k.hash.slice(-8) }))); });
app.post('/admin/keys/:suffix/revoke', admin, (req, res) => { const db = readDb(); const key = (db.keys || []).find(k => k.hash.endsWith(String(req.params.suffix).toLowerCase())); if (!key) return res.status(404).json({ error: 'Key not found' }); key.revoked = true; writeDb(db); res.json({ ok: true }); });
app.post('/keys/redeem', auth, (req, res) => {
  const raw = req.body && req.body.key; if (typeof raw !== 'string' || raw.trim().length < 10 || raw.trim().length > 100) return res.status(400).json({ error: 'Invalid key format' });
  const db = readDb(); db.keys ||= []; const key = db.keys.find(k => k.hash === keyHash(raw));
  if (!key || key.revoked || key.uses >= key.maxUses) return res.status(409).json({ error: 'Key invalid, revoked or already fully redeemed' });
  if ((key.redemptions || []).includes(req.user.sub)) return res.status(409).json({ error: 'This account already redeemed this key' });
  key.uses++; key.redemptions ||= []; key.redemptions.push(req.user.sub); const entitlement = grantEntitlement(db, req.user.sub, key.planId); writeDb(db);
  res.json({ ok: true, planId: entitlement.planId, expiresAt: entitlement.expiresAt, status: entitlement.status });
});
app.get('/admin/users', admin, (_req, res) => { const db = readDb(); res.json(Object.values(db.users).map(u => ({ ...publicUser(u), entitlement: db.entitlements[u.discordId] || { planId: 'free', status: 'free' } }))); });
ensureOwnerAccount().catch(e => console.error('Owner provisioning failed:', e.message));
app.listen(PORT, () => console.log(`Insane Straps API listening on ${PORT}`));
