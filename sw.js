self.addEventListener("push",event=>{
 let data={title:"Crown notification",body:"You have a new update.",url:"/"};
 try{if(event.data)data={...data,...event.data.json()};}catch(_){try{data.body=event.data.text();}catch(__){ }}
 event.waitUntil(self.registration.showNotification(data.title||"Crown notification",{
  body:data.body||"You have a new update.",
  icon:"/crown-icon.svg",
  badge:"/crown-icon.svg",
  tag:"crown-"+Date.now(),
  data:{url:data.url||"/"},
  renotify:true
 }));
});
self.addEventListener("notificationclick",event=>{
 event.notification.close();
 const target=new URL(event.notification.data?.url||"/",self.location.origin).href;
 event.waitUntil(clients.matchAll({type:"window",includeUncontrolled:true}).then(list=>{
  for(const client of list){if(new URL(client.url).origin===self.location.origin){client.focus();client.navigate(target);return;}}
  return clients.openWindow(target);
 }));
});