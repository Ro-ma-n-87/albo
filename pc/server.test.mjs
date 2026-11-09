import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import {createWorkspaceServer,emptyDatabase,mergeDatabase,privateVPNAddress} from './server.mjs';
const ids={job:'11111111-1111-4111-8111-111111111111',worker:'22222222-2222-4222-8222-222222222222',other:'33333333-3333-4333-8333-333333333333'};
const job=(title='Wartung')=>({id:ids.job,title,customer:'Familie Müller',address:'Teststraße 1',status:'In Arbeit',notes:''});
function removeTestDirectory(dir){const absolute=path.resolve(dir);assert.ok(absolute.startsWith(path.resolve(os.tmpdir())+path.sep)&&path.basename(absolute).startsWith('albo-'));fs.rmSync(absolute,{recursive:true,force:true});}
async function fixture(t){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'albo-test-'));let app=createWorkspaceServer({dataDir:dir,port:0});let address=await app.listen();let base='http://127.0.0.1:'+address.port;let cookie='';
const call=async(route,options={})=>{const response=await fetch(base+'/api/'+route,{...options,headers:{'Content-Type':'application/json',Cookie:cookie,...options.headers}});return {status:response.status,body:await response.json(),headers:response.headers};};
t.after(async()=>{await app.close();removeTestDirectory(dir);});
const auth=await call('local-session',{method:'POST',body:'{}'});assert.equal(auth.status,200,JSON.stringify(auth.body));cookie=auth.headers.get('set-cookie').split(';')[0];
return {call,dir,app,get base(){return base;},async restart(){await app.close();app=createWorkspaceServer({dataDir:dir,port:0});address=await app.listen();base='http://127.0.0.1:'+address.port;const auth=await call('local-session',{method:'POST',body:'{}'});cookie=auth.headers.get('set-cookie').split(';')[0];}};}
const sync=(f,snapshot,database,headers={})=>f.call('sync',{method:'POST',headers,body:JSON.stringify({workspaceID:snapshot.workspaceID,baseRevision:snapshot.revision,backup:{version:1,database,photos:snapshot.backup.photos}})});

test('PC edits survive restart; stale independent changes merge and conflicting changes do not overwrite',async t=>{
 const f=await fixture(t),start=(await f.call('workspace')).body;
 const first=structuredClone(start.backup.database);first.jobs.push(job());
 const created=await sync(f,start,first);assert.equal(created.status,200);
 const a=structuredClone(created.body.backup.database),b=structuredClone(a);
 a.jobs[0].notes='Vom Büro bearbeitet';
 assert.equal((await sync(f,created.body,a)).status,200);
 b.customers.push({id:ids.other,name:'Neuer Kunde',address:'Adresse',phone:'',email:''});
 const merged=await sync(f,created.body,b);assert.equal(merged.status,200);assert.equal(merged.body.backup.database.jobs[0].notes,'Vom Büro bearbeitet');
 b.jobs[0].notes='Offline am iPhone geändert';const conflict=await sync(f,created.body,b);assert.equal(conflict.status,409);assert.equal(conflict.body.conflicts[0].collection,'jobs');
 await f.restart();const restored=(await f.call('workspace')).body;assert.equal(restored.backup.database.jobs[0].notes,'Vom Büro bearbeitet');assert.equal(restored.backup.database.customers.length,1);
});
test('device tokens enforce worker permissions and revocation',async t=>{
 const f=await fixture(t),start=(await f.call('workspace')).body,db=structuredClone(start.backup.database);db.jobs.push(job());db.employees.push({id:ids.worker,name:'Marco',role:'Monteur',active:true});
 const ready=(await sync(f,start,db)).body;
 const paired=await f.call('keys',{method:'POST',body:JSON.stringify({role:'worker',employeeID:ids.worker,label:'iPhone Marco'})});assert.equal(paired.status,201);const headers={Authorization:'Bearer '+paired.body.token,Cookie:''};
 const denied=structuredClone(ready.backup.database);denied.jobs[0].title='Fremde Stammdaten ändern';assert.equal((await sync(f,ready,denied,headers)).status,403);
 const allowed=structuredClone(ready.backup.database);allowed.entries.push({id:ids.other,jobID:ids.job,start:100,end:400,paidSeconds:300,employee:'Marco'});const saved=await sync(f,ready,allowed,headers);assert.equal(saved.status,200);
 const unauthorized=await f.call('keys',{headers});assert.equal(unauthorized.status,403);
 const disabled=structuredClone(saved.body.backup.database);disabled.employees.find(e=>e.id===ids.worker).active=false;
 assert.equal((await sync(f,saved.body,disabled)).status,200);
 assert.equal((await f.call('workspace',{headers})).status,403);
 assert.equal((await f.call('keys/'+paired.body.id,{method:'DELETE'})).status,200);
 assert.equal((await f.call('workspace',{headers})).status,401);
 assert.ok(!fs.readFileSync(path.join(f.dir,'workspace.json'),'utf8').includes(paired.body.token),'Raw token must not be stored');
});
test('foreign origins, malformed data and absent authentication are rejected',async t=>{
 const f=await fixture(t);assert.equal((await f.call('workspace',{headers:{Cookie:''}})).status,401);
 assert.equal((await f.call('local-session',{method:'POST',headers:{Origin:'https://attacker.invalid'},body:'{}'})).status,403);
 const state=(await f.call('workspace')).body,db=structuredClone(state.backup.database);db.jobs.push({...job(),title:''});assert.equal((await sync(f,state,db)).status,400);
 assert.equal((await f.call('workspace')).body.revision,0);
});
test('invalid existing database is not replaced',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'albo-corrupt-')),file=path.join(dir,'workspace.json');
 try{fs.writeFileSync(file,'corrupt');assert.throws(()=>createWorkspaceServer({dataDir:dir,port:0}));assert.equal(fs.readFileSync(file,'utf8'),'corrupt');}finally{removeTestDirectory(dir);}
});
test('three-way deletion respects concurrent edits and independent clocks',()=>{
 const base=emptyDatabase();base.jobs.push(job());const local=structuredClone(base),remote=structuredClone(base);local.jobs=[];remote.jobs[0].notes='Neue Notiz';assert.throws(()=>mergeDatabase(base,local,remote),e=>e.status===409);
 const b=emptyDatabase(),a=structuredClone(b),c=structuredClone(b);a.clocks.Marco={accumulated:20};c.clocks.Salvatore={accumulated:10};assert.equal(Object.keys(mergeDatabase(b,a,c).clocks).length,2);
});
test('first administrative sync preserves native-format dates, photos, signatures and unrelated PC edits',async t=>{
 const f=await fixture(t),remote=(await f.call('workspace')).body;
 const admin=await f.call('keys',{method:'POST',body:JSON.stringify({role:'admin',label:'iPhone Verwaltung'})});
 const db=structuredClone(remote.backup.database),png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=';
 db.jobs.push(job());db.reports.push({id:ids.other,jobID:ids.job,date:815875200,author:'Salvatore',title:'Wartung',text:'Ölheizung geprüft.',materials:'Ölfilter',photos:[{id:ids.worker,filename:ids.worker+'.png',caption:'Heizungsanlage'}],measurements:[{id:'44444444-4444-4444-8444-444444444444',label:'Boden',length:3.5,width:2.4,quantity:1}],customerName:'Herr Müller',customerSignature:png,workerSignature:png,completed:true});
 const merged=await f.call('sync',{method:'POST',headers:{Authorization:'Bearer '+admin.body.token,Cookie:''},body:JSON.stringify({workspaceID:remote.workspaceID,baseRevision:null,backup:{version:1,database:db,photos:{[ids.worker+'.png']:png}}})});
 assert.equal(merged.status,200);assert.equal(merged.body.backup.database.reports[0].date,815875200);assert.equal(merged.body.backup.database.reports[0].customerSignature,png);assert.equal(merged.body.backup.photos[ids.worker+'.png'],png);assert.equal(merged.body.backup.database.templates.length,3);
});
test('signed baselines support long offline periods and reject tampered starting data',async t=>{
 const f=await fixture(t),original=(await f.call('workspace')).body;
 let current=original;
 for(let n=0;n<33;n++){const db=structuredClone(current.backup.database);db.employee='Verwaltung '+n;current=(await sync(f,current,db)).body;}
 const local=structuredClone(original.backup.database);local.jobs.push(job());
 const request={workspaceID:original.workspaceID,baseRevision:original.revision,baseSnapshot:{revision:original.revision,proof:original.proof,database:original.backup.database},backup:{version:1,database:local,photos:{}}};
 assert.equal((await f.call('sync',{method:'POST',body:JSON.stringify(request)})).status,200);
 request.baseSnapshot.database.employees[0].name='Manipulierter Ausgangsstand';
 assert.equal((await f.call('sync',{method:'POST',body:JSON.stringify(request)})).status,403);
});
test('private VPN API exposes only paired sync and never the local administration',async t=>{
 const f=await fixture(t),remote=http.createServer(f.app.remoteHandler);
 const address=await new Promise(resolve=>remote.listen(0,'127.0.0.1',()=>resolve(remote.address())));
 t.after(()=>new Promise(resolve=>remote.close(resolve)));
 const url='http://127.0.0.1:'+address.port;
 assert.equal((await fetch(url+'/api/local-session',{method:'POST',headers:{Host:'localhost'},body:'{}'})).status,403);
 assert.equal((await fetch(url+'/')).status,403);
 assert.equal((await fetch(url+'/api/workspace')).status,401);
 const login=await f.call('local-session',{method:'POST',body:'{}'}),cookie=login.headers.get('set-cookie').split(';')[0];
 assert.equal((await fetch(url+'/api/workspace',{headers:{Cookie:cookie}})).status,401);
 const paired=await f.call('keys',{method:'POST',body:JSON.stringify({role:'admin',label:'VPN iPhone'})});
 const headers={Authorization:'Bearer '+paired.body.token,'Content-Type':'application/json'};
 assert.equal((await fetch(url+'/api/keys',{headers})).status,403);
 const response=await fetch(url+'/api/workspace',{headers}),snapshot=await response.json();assert.equal(response.status,200);
 const database=structuredClone(snapshot.backup.database);database.jobs.push(job('Von der Baustelle'));
 const saved=await fetch(url+'/api/sync',{method:'POST',headers,body:JSON.stringify({workspaceID:snapshot.workspaceID,baseRevision:snapshot.revision,backup:{version:1,database,photos:{}}})});assert.equal(saved.status,200);
 assert.equal((await f.call('workspace')).body.backup.database.jobs[0].title,'Von der Baustelle');
 await f.call('keys/'+paired.body.id,{method:'DELETE'});
 assert.equal((await fetch(url+'/api/workspace',{headers})).status,401);
});
test('VPN listener is restricted to its private overlay address range',()=>{
 for(const address of ['100.64.0.1','100.80.10.20','100.127.255.254'])assert.equal(privateVPNAddress(address),true);
 for(const address of ['0.0.0.0','8.8.8.8','192.168.1.1','100.63.255.255','100.128.0.1','100.80.10.999',undefined])assert.equal(privateVPNAddress(address),false);
 assert.throws(()=>createWorkspaceServer({vpnHost:'0.0.0.0'}),/NetBird-Adresse/);
});
