const C="fbs-v4",F=["./","./index.html","./icon.svg","./config.js","./manifest.webmanifest"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(F)));self.skipWaiting()});
self.addEventListener("activate",e=>e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C).map(x=>caches.delete(x))))));
self.addEventListener("fetch",e=>{const r=e.request;if(r.method!=="GET"||new URL(r.url).origin!==location.origin)return;
e.respondWith(fetch(r).then(x=>{const y=x.clone();caches.open(C).then(c=>c.put(r,y));return x}).catch(()=>caches.match(r).then(m=>m||caches.match("./index.html"))))});
self.addEventListener("push",e=>{let d={};try{d=e.data?e.data.json():{}}catch(x){d={title:"FBStore Academy",body:e.data?e.data.text():""}}
e.waitUntil(self.registration.showNotification(d.title||"FBStore Academy",{body:d.body||"",icon:"./icon-192.png",badge:"./icon-192.png",data:{url:d.url||"./"}}))});
self.addEventListener("notificationclick",e=>{e.notification.close();const u=new URL(e.notification.data?.url||"./",self.registration.scope).href;
e.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(l=>{for(const c of l){if(c.url.startsWith(self.registration.scope)&&"focus"in c){c.navigate(u);return c.focus()}}return clients.openWindow(u)}))});
