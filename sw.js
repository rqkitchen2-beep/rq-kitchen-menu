const V="rq-pos-v2";
const SHELL=["/", "/index.html", "/manifest.webmanifest", "/logo.png", "/icon-192.png", "/icon-512.png", "/icon-180.png", "/img/alain_new.webp", "/img/beef_hotdog.webp", "/img/buffalo.webp", "/img/chicken_jalapeno.webp", "/img/chicken_volcano.webp", "/img/classic_fries.webp", "/img/classic_huwar.webp", "/img/coleslaw.webp", "/img/combo_photo.webp", "/img/crab_salad.webp", "/img/crab_salad_sushi.webp", "/img/crispy_chicken.webp", "/img/crispy_shrimp_roll.webp", "/img/crunchy_crab.webp", "/img/double_beef_jal.webp", "/img/double_huwar.webp", "/img/double_shrimp.webp", "/img/double_wagyu.webp", "/img/dynamite_shrimp.webp", "/img/futomaki.webp", "/img/honey_tender.webp", "/img/rq_beef_hotdog.webp", "/img/rq_classic_hotdog.webp", "/img/rq_huwar.webp", "/img/rq_special_hotdog.webp", "/img/shrimp_wrap.webp", "/img/signature_fries.webp", "/img/spicy_tempura.webp"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting()));});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==V).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener("fetch",e=>{
  const r=e.request; if(r.method!=="GET") return;
  const u=new URL(r.url);
  if(u.hostname.endsWith("supabase.co")) return; // live data never cached here
  if(r.mode==="navigate"){
    e.respondWith(fetch(r).then(res=>{const c=res.clone();caches.open(V).then(x=>x.put("/index.html",c));return res;}).catch(()=>caches.match("/index.html")));
    return;
  }
  e.respondWith(caches.match(r).then(hit=>hit||fetch(r).then(res=>{
    if(res.ok||res.type==="opaque"){const c=res.clone();caches.open(V).then(x=>x.put(r,c));}
    return res;
  }).catch(()=>hit)));
});
