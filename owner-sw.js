const C='rq-owner-v1';
self.addEventListener('install',e=>{self.skipWaiting();e.waitUntil(caches.open(C).then(c=>c.addAll(['/owner','/owner-192.png']).catch(()=>{})))});
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==location.origin)return;
 if(e.request.mode==='navigate'){e.respondWith(fetch(e.request).then(r=>{const c=r.clone();caches.open(C).then(x=>x.put('/owner',c));return r}).catch(()=>caches.match('/owner')));return}
 e.respondWith(caches.match(e.request).then(r=>r||fetch(e.request)))});
self.addEventListener('push',e=>{let d={};try{d=e.data.json()}catch(_){d={title:'RQ Owner',body:e.data?e.data.text():''}}
 e.waitUntil(self.registration.showNotification(d.title||'RQ Owner',{body:d.body||'',icon:'/owner-192.png',badge:'/owner-192.png',tag:d.tag,data:{url:d.url||'/'},dir:'rtl',lang:'ar'}))});
self.addEventListener('notificationclick',e=>{e.notification.close();const url=new URL((e.notification.data&&e.notification.data.url)||'/',self.location.origin).href;
 e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(l=>{for(const c of l){if('focus' in c){c.navigate&&c.navigate(url);return c.focus()}}return clients.openWindow(url)}))});
