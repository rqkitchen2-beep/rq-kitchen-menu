self.addEventListener("install",()=>self.skipWaiting());
self.addEventListener("activate",e=>e.waitUntil(self.clients.claim()));
self.addEventListener("push",e=>{
  let d={title:"🍔 طلبك جاهز!",body:"تفضّل استلم طلبك من RQ Kitchen",url:"/",tag:"rq"};
  try{d=Object.assign(d,e.data.json())}catch(_){}
  e.waitUntil((async()=>{
    await self.registration.showNotification(d.title,{body:d.body,icon:"/icon-192.png",badge:"/badge.png",tag:d.tag,renotify:true,requireInteraction:true,vibrate:[500,200,500,200,800],data:{url:d.url},dir:"rtl",lang:"ar"});
    const cs=await self.clients.matchAll({type:"window"}); cs.forEach(c=>c.postMessage("refresh"));
  })());
});
self.addEventListener("notificationclick",e=>{
  e.notification.close(); const url=e.notification.data&&e.notification.data.url||"/";
  e.waitUntil((async()=>{const cs=await self.clients.matchAll({type:"window",includeUncontrolled:true});
    for(const c of cs){ if(new URL(c.url).pathname===url){return c.focus()} }
    return self.clients.openWindow(url);})());
});
