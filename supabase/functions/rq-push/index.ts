// RQ Kitchen push notifications: called by the app_orders trigger (pg_net) and by
// app_admin_broadcast, with a shared secret. Sends APNs alerts to the customer, branch
// and driver apps, in each device's language.
const SB = Deno.env.get('SUPABASE_URL')!;
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const TOPIC: Record<string, string> = { customer: 'com.rqkitchen.app', driver: 'com.rqkitchen.driver', branch: 'com.rqkitchen.branch' };

type Msg = { ar: [string, string]; en: [string, string] };
let CFG: any = null;
let JWT = { t: '', at: 0 };

async function db(path: string, init: RequestInit = {}) {
  const r = await fetch(SB + '/rest/v1/' + path, { ...init, headers: { apikey: SRK, Authorization: 'Bearer ' + SRK, 'Content-Type': 'application/json', ...(init.headers || {}) } });
  const txt = await r.text();
  try { return JSON.parse(txt); } catch { return txt; }
}
async function config() {
  if (!CFG) CFG = await db('rpc/app_push_config', { method: 'POST', body: '{}' });
  return CFG;
}
function b64u(b: ArrayBuffer | Uint8Array | string) {
  const bytes = typeof b === 'string' ? new TextEncoder().encode(b) : new Uint8Array(b as ArrayBuffer);
  let s = ''; bytes.forEach((x) => s += String.fromCharCode(x));
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
async function apnsJwt() {
  const now = Math.floor(Date.now() / 1000);
  if (JWT.t && now - JWT.at < 2400) return JWT.t;
  const c = await config();
  const pem = String(c.apns_key).replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (ch) => ch.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const head = b64u(JSON.stringify({ alg: 'ES256', kid: c.key_id }));
  const body = b64u(JSON.stringify({ iss: c.team_id, iat: now }));
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(head + '.' + body));
  JWT = { t: head + '.' + body + '.' + b64u(sig), at: now };
  return JWT.t;
}

async function sendOne(token: string, app: string, title: string, body: string, data: Record<string, unknown> = {}) {
  const payload = { aps: { alert: { title, body }, sound: 'default', 'interruption-level': app === 'branch' ? 'time-sensitive' : 'active' }, ...data };
  const r = await fetch('https://api.push.apple.com/3/device/' + token, {
    method: 'POST',
    headers: { authorization: 'bearer ' + await apnsJwt(), 'apns-topic': TOPIC[app], 'apns-push-type': 'alert', 'apns-priority': '10', 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const txt = r.status === 200 ? '' : await r.text();
  if (r.status === 410 || /BadDeviceToken|Unregistered|DeviceTokenNotForTopic/.test(txt)) {
    await db('app_push_tokens?token=eq.' + encodeURIComponent(token), { method: 'DELETE' });
  }
  return { status: r.status, reason: txt };
}
async function sendTo(filter: string, m: Msg, data: Record<string, unknown> = {}) {
  const rows = await db('app_push_tokens?select=token,app,lang&' + filter);
  if (!Array.isArray(rows) || !rows.length) return [];
  const out: any[] = [];
  for (let i = 0; i < rows.length; i += 50) {
    const part = rows.slice(i, i + 50);
    out.push(...await Promise.all(part.map((x: any) => { const t = x.lang === 'en' ? m.en : m.ar; return sendOne(x.token, x.app, t[0], t[1], data).catch((e) => ({ status: 0, reason: String(e) })); })));
  }
  return out;
}

const KIND: Record<string, { ar: string; en: string }> = { delivery: { ar: 'توصيل', en: 'Delivery' }, pickup: { ar: 'استلام', en: 'Pickup' } };

async function handle(ev: any) {
  const o = ev.order || {}; const n = '#' + o.order_no; const out: any = {};
  const branchF = 'app=eq.branch&branch_id=eq.' + encodeURIComponent(o.branch_id);
  const cust = (m: Msg) => o.customer_id ? sendTo('app=eq.customer&customer_id=eq.' + o.customer_id, m, { url: '#/order/' + o.id }) : Promise.resolve([]);
  if (ev.op === 'INSERT') {
    const k = KIND[o.kind] || { ar: '', en: '' };
    out.branch = await sendTo(branchF, {
      ar: ['طلب جديد ' + n + ' 🔔', k.ar + ' · ' + o.total + ' درهم' + (o.name ? ' · ' + o.name : '')],
      en: ['New order ' + n + ' 🔔', k.en + ' · AED ' + o.total + (o.name ? ' · ' + o.name : '')],
    });
    return out;
  }
  if (ev.old_status !== o.status) {
    const s = o.status;
    if (s === 'accepted') out.customer = await cust({
      ar: ['تم قبول طلبك ' + n + ' ✅', o.eta_minutes ? 'يكون جاهز خلال ' + o.eta_minutes + ' دقيقة تقريباً' : 'بدأنا نجهز طلبك'],
      en: ['Order ' + n + ' accepted ✅', o.eta_minutes ? 'Ready in about ' + o.eta_minutes + ' min' : "We've started preparing your order"] });
    else if (s === 'preparing') out.customer = await cust({
      ar: ['طلبك قيد التحضير 👨‍🍳', 'نجهز طلبك ' + n + ' الحين'],
      en: ['Your order is being prepared 👨‍🍳', "We're preparing order " + n + ' now'] });
    else if (s === 'ready' && o.kind === 'pickup') out.customer = await cust({
      ar: ['طلبك جاهز للاستلام 🎉', 'تفضل للفرع واستلم طلبك ' + n],
      en: ['Your order is ready for pickup 🎉', 'Come to the branch to collect order ' + n] });
    else if (s === 'on_way') out.customer = await cust({
      ar: ['طلبك في الطريق 🛵', 'السائق متجه لك الحين بطلبك ' + n],
      en: ['Your order is on the way 🛵', 'The driver is heading to you with order ' + n] });
    else if (s === 'delivered') out.customer = await cust({
      ar: ['تم توصيل طلبك 🍔', 'بالعافية! قيّم طلبك من التطبيق'],
      en: ['Your order was delivered 🍔', 'Enjoy your meal! Rate your order in the app'] });
    else if (s === 'rejected') out.customer = await cust({
      ar: ['نعتذر، ما قدرنا نقبل طلبك ' + n, o.cancel_reason || 'تواصل مع الفرع للتفاصيل'],
      en: ["Sorry, we couldn't accept order " + n, 'Please contact the branch for details'] });
    else if (s === 'cancelled') {
      if (ev.old_status === 'new' || ev.old_status === 'accepted') out.branch = await sendTo(branchF, {
        ar: ['تم إلغاء الطلب ' + n, 'العميل ألغى الطلب'],
        en: ['Order ' + n + ' cancelled', 'The customer cancelled the order'] });
      if (o.driver_id) out.driver = await sendTo('app=eq.driver&driver_id=eq.' + o.driver_id, {
        ar: ['تم إلغاء الطلب ' + n, 'لا تحتاج توصله'],
        en: ['Order ' + n + ' cancelled', 'No need to deliver it'] });
    }
    if (o.kind === 'delivery' && !o.driver_id && s === 'accepted') {
      const drivers = await db('app_drivers?select=id&active=eq.true&online=eq.true&or=(branch_id.is.null,branch_id.eq.' + encodeURIComponent(o.branch_id) + ')');
      if (Array.isArray(drivers) && drivers.length) {
        out.drivers = await sendTo('app=eq.driver&driver_id=in.(' + drivers.map((d: any) => d.id).join(',') + ')', {
          ar: ['طلب توصيل جديد ' + n + ' 🛵', 'اضغط عشان تقبله قبل غيرك'],
          en: ['New delivery order ' + n + ' 🛵', 'Tap to accept it before anyone else'] }, { url: '#' });
      }
    }
  }
  return out;
}

function tally(list: any[]) {
  const r: Record<string, number> = { sent: 0, failed: 0 };
  for (const x of list) { if (x.status === 200) r.sent++; else r.failed++; }
  return r;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('ok');
  try {
    const c = await config();
    if (!c || !c.secret || req.headers.get('x-rq-secret') !== c.secret) return new Response('forbidden', { status: 403 });
    const ev = await req.json();
    let out: any;
    if (ev.broadcast) {
      const res = await sendTo('app=eq.customer', { ar: [ev.title_ar, ev.body_ar || ''], en: [ev.title_en || ev.title_ar, ev.body_en || ev.body_ar || ''] }, { url: '#/home' });
      out = { broadcast: tally(res) };
    } else if (ev.test) {
      out = { test: await sendTo(ev.filter || 'app=eq.' + (ev.app || 'customer'), { ar: [ev.title || 'RQ Kitchen', ev.body || 'إشعار تجريبي ✅'], en: [ev.title || 'RQ Kitchen', ev.body || 'Test notification ✅'] }) };
    } else out = await handle(ev);
    return new Response(JSON.stringify(out), { headers: { 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
