import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {isIPv4} from 'node:net';

const here=path.dirname(fileURLToPath(import.meta.url));
const fields=['jobs','reports','entries','templates','employees','customers'];
const uuid=()=>crypto.randomUUID().toUpperCase();
const clone=v=>structuredClone(v);
const key=id=>String(id).toUpperCase();
const canonical=v=>JSON.stringify(v&&typeof v==='object'?(Array.isArray(v)?v.map(x=>JSON.parse(canonical(x))):Object.fromEntries(Object.keys(v).sort().map(k=>[k,JSON.parse(canonical(v[k]))]))):v);
const equal=(a,b)=>a===undefined||b===undefined?a===b:canonical(a)===canonical(b);
const hash=s=>crypto.createHash('sha256').update(s).digest('hex');
const loopback=ip=>ip==='127.0.0.1'||ip==='::1'||ip==='::ffff:127.0.0.1';
export const privateVPNAddress=ip=>typeof ip==='string'&&isIPv4(ip)&&ip.split('.')[0]==='100'&&Number(ip.split('.')[1])>=64&&Number(ip.split('.')[1])<=127;
const failure=(status,message,extra={})=>Object.assign(new Error(message),{status,...extra});
const text=(v,max=2000)=>typeof v==='string'&&v.length<=max;
const validID=v=>typeof v==='string'&&/^[A-Fa-f0-9]{8}-(?:[A-Fa-f0-9]{4}-){3}[A-Fa-f0-9]{12}$/.test(v);

export function emptyDatabase(){return {jobs:[],reports:[],entries:[],templates:[],employees:[],customers:[],clocks:{},employee:'Salvatore'};}
function normalize(db){const result={...db};for(const field of fields)result[field]=db[field]??[];result.clocks=db.clocks??{};delete result.clock;return result;}

export function mergeDatabase(base,local,remote){
  base=normalize(base);local=normalize(local);remote=normalize(remote);
  const merged=clone(remote),conflicts=[];
  for(const field of fields){
    const maps=[base,local,remote].map(db=>new Map(db[field].map(row=>[key(row.id),row]))),rows=[];
    for(const id of new Set(maps.flatMap(m=>[...m.keys()]))){
      const [before,mine,theirs]=maps.map(m=>m.get(id));let result;
      if(equal(mine,before))result=theirs;
      else if(equal(theirs,before)||equal(mine,theirs))result=mine;
      else{conflicts.push({collection:field,id});continue;}
      if(result!==undefined)rows.push(clone(result));
    }
    merged[field]=rows;
  }
  merged.clocks={};
  for(const name of new Set([base,local,remote].flatMap(db=>Object.keys(db.clocks)))){
    const [before,mine,theirs]=[base,local,remote].map(db=>db.clocks[name]);let result;
    if(equal(mine,before))result=theirs;
    else if(equal(theirs,before)||equal(mine,theirs))result=mine;
    else{conflicts.push({collection:'clocks',id:name});continue;}
    if(result!==undefined)merged.clocks[name]=clone(result);
  }
  if(conflicts.length)throw failure(409,'Dieselben Datensätze wurden auf mehreren Geräten geändert. Die lokalen Änderungen bleiben erhalten.',{conflicts});
  return merged;
}

function validate(db,photos,{allowMissingPhotos=false}={}){
  for(const field of fields){
    if(!Array.isArray(db[field])||db[field].length>20000)throw failure(400,'Ungültige Datensammlung: '+field);
    const ids=new Set();for(const row of db[field]){if(!row||!validID(row.id)||ids.has(key(row.id)))throw failure(400,'Ungültige oder doppelte ID in '+field);ids.add(key(row.id));}
  }
  const jobs=new Set(db.jobs.map(j=>key(j.id)));
  for(const j of db.jobs)if(!text(j.title,200)||!j.title.trim()||!text(j.customer,100)||!j.customer.trim()||!text(j.address,300)||!['Geplant','In Arbeit','Abgeschlossen'].includes(j.status)||!text(j.notes??'',5000))throw failure(400,'Ungültige Baustelle.');
  for(const r of db.reports){
    if(!jobs.has(key(r.jobID))||!text(r.title,200)||!r.title.trim()||!text(r.author,100)||!r.author.trim()||!text(r.text,30000)||!r.text.trim()||!text(r.materials,10000)||!text(r.customerName,100)||!Number.isFinite(r.date)||typeof r.completed!=='boolean'||!Array.isArray(r.photos)||!Array.isArray(r.measurements))throw failure(400,'Ungültiger Bericht.');
    if(r.completed&&(!text(r.customerName,100)||!r.customerName.trim()||!r.customerSignature||!r.workerSignature))throw failure(400,'Abgeschlossene Berichte brauchen Kundenname und beide Unterschriften.');
    for(const signature of [r.customerSignature,r.workerSignature].filter(Boolean))if(!validImage(signature))throw failure(400,'Ungültige Unterschrift.');
    for(const p of r.photos)if(!validID(p.id)||!safePhotoName(p.filename)||(!(allowMissingPhotos&&photos[p.filename]===undefined)&&!validImage(photos[p.filename]))||!text(p.caption,1000))throw failure(400,'Foto fehlt oder ist ungültig.');
    for(const m of r.measurements)if(!validID(m.id)||!text(m.label,200)||![m.length,m.width].every(v=>Number.isFinite(v)&&v>0)||!Number.isInteger(m.quantity)||m.quantity<1||m.quantity>999||!Number.isFinite(m.length*m.width*m.quantity))throw failure(400,'Ungültiges Aufmaß.');
  }
  for(const e of db.entries)if(!jobs.has(key(e.jobID))||![e.start,e.end].every(Number.isFinite)||e.end<e.start||(e.paidSeconds!==undefined&&(!Number.isFinite(e.paidSeconds)||e.paidSeconds<0||e.paidSeconds>e.end-e.start+1)))throw failure(400,'Ungültige Arbeitszeit.');
  for(const t of db.templates)if(!text(t.name,100)||!t.name.trim()||!text(t.text,30000))throw failure(400,'Ungültige Vorlage.');
  const names=new Set();for(const e of db.employees){if(!text(e.name,100)||!e.name.trim()||names.has(e.name)||!text(e.role,100)||typeof e.active!=='boolean')throw failure(400,'Ungültiger oder doppelter Mitarbeiter.');names.add(e.name);}
  for(const c of db.customers)if(!text(c.name,100)||!c.name.trim()||!text(c.address,300)||!text(c.phone,100)||!text(c.email,200))throw failure(400,'Ungültiger Kunde.');
  if(!db.clocks||Array.isArray(db.clocks)||typeof db.clocks!=='object')throw failure(400,'Ungültige Zeiterfassung.');
  for(const [name,c] of Object.entries(db.clocks)){if(!db.employees.some(e=>e.name===name&&e.active)||!jobs.has(key(c.jobID))||!Number.isFinite(c.started)||!Number.isFinite(c.accumulated)||c.accumulated<0||(c.segmentStart!==undefined&&c.segmentStart!==null&&!Number.isFinite(c.segmentStart)))throw failure(400,'Ungültige laufende Zeiterfassung.');}
}
function safePhotoName(name){return typeof name==='string'&&/^[A-Fa-f0-9-]{36}\.(?:jpg|png)$/.test(name)&&validID(name.slice(0,36));}
function validImage(value){if(typeof value!=='string'||value.length>12*1024*1024||!/^[a-zA-Z0-9+/]*={0,2}$/.test(value))return false;const bytes=Buffer.from(value,'base64');return bytes.length>8&&((bytes[0]===255&&bytes[1]===216&&bytes[2]===255)||bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])));}
function workerMayChange(user,before,after){
  if(user.role==='admin')return;
  const employee=before.employees.find(e=>key(e.id)===key(user.employeeID));
  if(!employee?.active)throw failure(403,'Mitarbeiterzugang ist nicht aktiv.');
  for(const field of ['jobs','templates','employees','customers'])if(!equal(before[field],after[field]))throw failure(403,'Nur die Verwaltung darf '+field+' bearbeiten.');
  for(const field of ['reports','entries']){
    const b=new Map(before[field].map(r=>[key(r.id),r])),a=new Map(after[field].map(r=>[key(r.id),r]));
    for(const id of new Set([...a.keys(),...b.keys()]))if(!equal(a.get(id),b.get(id))){
      for(const row of [a.get(id),b.get(id)].filter(Boolean))if((field==='reports'?row.author:row.employee)!==employee.name)throw failure(403,'Fremde Berichte und Arbeitszeiten dürfen nicht geändert werden.');
    }
  }
  for(const name of new Set([...Object.keys(before.clocks),...Object.keys(after.clocks)]))if(name!==employee.name&&!equal(before.clocks[name],after.clocks[name]))throw failure(403,'Fremde Zeiterfassung darf nicht geändert werden.');
}

export function createWorkspaceServer({dataDir=path.join(here,'data'),host='127.0.0.1',port=8787,tls,allowInsecureLAN=false,vpnHost,vpnPort=8788}={}){
  if(vpnHost&&!privateVPNAddress(vpnHost))throw Error('Für die private VPN-Verbindung ist die NetBird-Adresse des PCs aus 100.64.0.0/10 erforderlich.');
  if(vpnHost&&(!loopback(host)||tls))throw Error('Die lokale Verwaltung muss im privaten VPN-Modus ausschließlich auf localhost laufen.');
  if(!loopback(host)&&!tls&&!allowInsecureLAN)throw Error('Für Netzwerkbetrieb HTTPS konfigurieren oder den unverschlüsselten LAN-Test ausdrücklich mit --allow-insecure-lan aktivieren.');
  fs.mkdirSync(dataDir,{recursive:true});const filename=path.join(dataDir,'workspace.json');
  let state;
  if(fs.existsSync(filename)){
    state=JSON.parse(fs.readFileSync(filename,'utf8'));
    if(state.schema!==1||!Array.isArray(state.history)||!Array.isArray(state.keys))throw Error('Datenbankformat nicht lesbar. Vorhandene Datei wird nicht überschrieben.');
    validate(normalize(state.database),state.photos);
  }else{
    const database=emptyDatabase();database.employees=[{id:'A1B00000-0000-4000-8000-000000000001',name:'Salvatore',role:'Monteur',active:true}];
    database.templates=[
      {id:'A1B00000-0000-4000-8000-000000001001',name:'Wartung',text:'Anlage / Gerät:\nDurchgeführte Wartung:\nMesswerte:\nFestgestellte Mängel:\nEmpfohlene Maßnahmen:'},
      {id:'A1B00000-0000-4000-8000-000000001002',name:'Reparatur',text:'Gemeldete Störung:\nUrsache:\nDurchgeführte Arbeiten:\nFunktionsprüfung:\nWeitere Maßnahmen:'},
      {id:'A1B00000-0000-4000-8000-000000001003',name:'Kundendienst',text:'Kundenauftrag:\nDurchgeführte Arbeiten:\nErgebnis / Übergabe:\nOffene Punkte:'}
    ];
    state={schema:1,workspaceID:uuid(),revision:0,database,photos:{},keys:[],signingKey:crypto.randomBytes(32).toString('hex'),history:[{revision:0,database:clone(database)}]};
  }
  function commit(next){const temporary=filename+'.'+crypto.randomUUID()+'.tmp';const fd=fs.openSync(temporary,'wx',0o600);try{fs.writeFileSync(fd,JSON.stringify(next));fs.fsyncSync(fd);}finally{fs.closeSync(fd);}try{fs.renameSync(temporary,filename);}catch(e){try{fs.unlinkSync(temporary);}catch{}throw e;}state=next;}
  if(!fs.existsSync(filename))commit(state);
  if(!state.signingKey){const next=clone(state);next.signingKey=crypto.randomBytes(32).toString('hex');commit(next);}
  const sessions=new Map();
  const proof=(revision,database)=>crypto.createHmac('sha256',state.signingKey).update(canonical({workspaceID:state.workspaceID,revision,database})).digest('hex');
  const view=()=>({workspaceID:state.workspaceID,revision:state.revision,proof:proof(state.revision,state.database),backup:{version:1,database:state.database,photos:state.photos}});
  const respond=(res,status,body,headers={})=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...headers});res.end(JSON.stringify(body));};
  async function body(req){let size=0;const chunks=[];for await(const chunk of req){size+=chunk.length;if(size>64*1024*1024)throw failure(413,'Datenpaket ist größer als 64 MB.');chunks.push(chunk);}try{return JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw failure(400,'Ungültige JSON-Daten.');}}
  function authorized(req,remote=false){
    const bearer=/^Bearer ([a-f0-9]{64})$/i.exec(req.headers.authorization||'');
    if(bearer){const result=state.keys.find(k=>k.hash===hash(bearer[1]));if(result){if(result.role==='worker'&&!state.database.employees.some(e=>key(e.id)===key(result.employeeID)&&e.active))throw failure(403,'Mitarbeiterzugang ist nicht aktiv.');return result;}}
    if(remote)throw failure(401,'Für den Baustellenzugriff ist ein eigener Kopplungsschlüssel erforderlich.');
    const cookie=/(?:^|;\s*)alboSession=([a-f0-9]{64})(?:;|$)/.exec(req.headers.cookie||'');const session=cookie&&sessions.get(cookie[1]);
    if(session&&session.expires>Date.now())return {role:'admin',id:'local'};
    throw failure(401,'Bitte anmelden oder Gerät koppeln.');
  }
  const handler=async(req,res,remote=false)=>{
    try{
      const url=new URL(req.url,'http://localhost');
      if(remote&&!((req.method==='GET'&&url.pathname==='/api/workspace')||(req.method==='POST'&&url.pathname==='/api/sync')))throw failure(403,'Über die Baustellenverbindung ist nur der Datenabgleich freigegeben.');
      if(req.headers.origin&&req.headers.origin!==`${tls?'https':'http'}://${req.headers.host}`)throw failure(403,'Anfrage von fremdem Ursprung abgelehnt.');
      if(req.headers['sec-fetch-site']==='cross-site')throw failure(403,'Fremde Website darf nicht auf diese Verwaltung zugreifen.');
      if(req.method==='POST'&&url.pathname==='/api/local-session'){
        if(!loopback(req.socket.remoteAddress))throw failure(403,'Die lokale PC-Anmeldung ist nur direkt an diesem PC möglich.');
        const hostName=(req.headers.host||'').toLowerCase();if(!/^(localhost|127\.0\.0\.1|\[::1\])(?::\d+)?$/.test(hostName))throw failure(403,'Bitte die Verwaltung über localhost öffnen.');
        const token=crypto.randomBytes(32).toString('hex');sessions.set(token,{expires:Date.now()+8*3600000});
        return respond(res,200,{ok:true},{'Set-Cookie':`alboSession=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800${tls?'; Secure':''}`});
      }
      if(url.pathname.startsWith('/api/')){
        const user=authorized(req,remote);
        if(req.method==='GET'&&url.pathname==='/api/workspace')return respond(res,200,{...view(),identity:{role:user.role,employeeID:user.employeeID??null}});
        if(req.method==='GET'&&url.pathname==='/api/keys'){if(user.role!=='admin')throw failure(403,'Nur Verwaltung.');return respond(res,200,{keys:state.keys.map(({hash,...rest})=>rest)});}
        if(req.method==='POST'&&url.pathname==='/api/keys'){
          if(user.role!=='admin')throw failure(403,'Nur Verwaltung darf Geräte koppeln.');const request=await body(req);
          if(!['admin','worker'].includes(request.role)||!text(request.label,100)||!request.label.trim())throw failure(400,'Gerätename und Rolle fehlen.');
          if(request.role==='worker'&&!state.database.employees.some(e=>e.active&&key(e.id)===key(request.employeeID)))throw failure(400,'Aktiven Mitarbeiter auswählen.');
          const token=crypto.randomBytes(32).toString('hex'),record={id:uuid(),hash:hash(token),role:request.role,label:request.label,employeeID:request.employeeID??null,created:new Date().toISOString()};
          const next=clone(state);next.keys.push(record);commit(next);return respond(res,201,{token,id:record.id});
        }
        if(req.method==='DELETE'&&url.pathname.startsWith('/api/keys/')){if(user.role!=='admin')throw failure(403,'Nur Verwaltung.');const next=clone(state);next.keys=next.keys.filter(k=>k.id!==decodeURIComponent(url.pathname.slice(10)));commit(next);return respond(res,200,{ok:true});}
        if(req.method==='POST'&&url.pathname==='/api/sync'){
          const request=await body(req);
          if(request.workspaceID!==state.workspaceID)throw failure(409,'Anderer Arbeitsbereich. Bitte die Verbindung prüfen.');
          if(!request.backup||request.backup.version!==1||!request.backup.photos||Array.isArray(request.backup.photos)||typeof request.backup.photos!=='object'||!(request.baseRevision===null||Number.isInteger(request.baseRevision)))throw failure(400,'Ungültiges Synchronisierungspaket.');
          if(request.baseRevision===null&&user.role!=='admin')throw failure(403,'Vor der ersten Mitarbeitersynchronisierung die PC-Daten laden.');
          let base=request.baseRevision===null?{database:emptyDatabase()}:state.history.find(v=>v.revision===request.baseRevision);
          if(request.baseSnapshot){
            const candidate=request.baseSnapshot;
            if(candidate.revision!==request.baseRevision||typeof candidate.proof!=='string'||!/^[a-f0-9]{64}$/.test(candidate.proof)||!candidate.database)throw failure(400,'Ungültiger Ausgangsstand.');
            const expected=proof(candidate.revision,candidate.database);
            if(!crypto.timingSafeEqual(Buffer.from(expected,'hex'),Buffer.from(candidate.proof,'hex')))throw failure(403,'Der Ausgangsstand konnte nicht bestätigt werden. Lokale Änderungen bleiben erhalten.');
            base={database:candidate.database};
          }
          if(!base)throw failure(409,'Der Ausgangsstand ist nicht mehr verfügbar. Bitte lokale Daten zuerst sichern und mit der Verwaltung abgleichen.');
          const local=normalize(request.backup.database||{}),current=normalize(state.database);
          const photos={...state.photos};for(const [name,bytes] of Object.entries(request.backup.photos)){if(!safePhotoName(name)||!validImage(bytes))throw failure(400,'Ungültiger Fotoanhang.');if(photos[name]&&photos[name]!==bytes)throw failure(409,'Foto-ID wurde mit anderem Inhalt verwendet.');photos[name]=bytes;}
          validate(local,photos,{allowMissingPhotos:true});
          // Compare the worker's edits to their own starting snapshot, not to newer remote edits.
          workerMayChange(user,normalize(base.database),local);
          const database=mergeDatabase(base.database,local,current);validate(database,photos);
          if(!database.employees.some(e=>e.active))throw failure(400,'Mindestens ein aktiver Mitarbeiter ist erforderlich.');
          const referenced=new Set(database.reports.flatMap(r=>r.photos.map(p=>p.filename)));
          const next=clone(state);next.database=database;next.photos=Object.fromEntries(Object.entries(photos).filter(([name])=>referenced.has(name)));next.revision++;next.history.push({revision:next.revision,database:clone(database)});next.history=next.history.slice(-30);commit(next);
          return respond(res,200,view());
        }
        throw failure(404,'API nicht gefunden.');
      }
      const resources={'/':['index.html','text/html; charset=utf-8'],'/app.js':['app.js','application/javascript; charset=utf-8'],'/lucide.js':['vendor/lucide.min.js','application/javascript; charset=utf-8'],'/style.css':['style.css','text/css; charset=utf-8'],'/reference.png':['../ALBOConnect/Assets.xcassets/Reference.imageset/reference.png','image/png']};
      if(req.method!=='GET'||!resources[url.pathname])throw failure(404,'Seite nicht gefunden.');
      const [file,type]=resources[url.pathname];res.writeHead(200,{'Content-Type':type,'X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'",'Cache-Control':'no-store'});res.end(fs.readFileSync(path.join(here,file)));
    }catch(error){respond(res,error.status||500,{error:error.status?error.message:'Speichern oder Verarbeiten fehlgeschlagen. Vorhandene Daten bleiben erhalten.',...(error.conflicts?{conflicts:error.conflicts}:{})});}
  };
  const localHandler=(req,res)=>handler(req,res,false),remoteHandler=(req,res)=>handler(req,res,true);
  const server=tls?https.createServer(tls,localHandler):http.createServer(localHandler);server.requestTimeout=30000;
  const vpnServer=vpnHost?http.createServer(remoteHandler):null;if(vpnServer)vpnServer.requestTimeout=30000;
  const start=(listener,p,h)=>new Promise((resolve,reject)=>{listener.once('error',reject);listener.listen(p,h,()=>resolve(listener.address()));});
  const stop=listener=>new Promise(resolve=>listener?.listening?listener.close(resolve):resolve());
  return {server,vpnServer,remoteHandler,async listen(){try{const address=await start(server,port,host);if(vpnServer)address.vpn=await start(vpnServer,vpnPort,vpnHost);return address;}catch(error){await Promise.all([stop(server),stop(vpnServer)]);throw error;}},async close(){await Promise.all([stop(server),stop(vpnServer)]);},snapshot:()=>clone(view())};
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const lan=process.argv.includes('--lan'),allowInsecureLAN=process.argv.includes('--allow-insecure-lan');
  const privateVPN=process.argv.includes('--private-vpn');
  if(privateVPN&&!process.env.ALBO_VPN_IP)throw Error('Die NetBird-IP des Büro-PCs fehlt. Starte Start-Baustelle-Windows.cmd.');
  if(privateVPN&&lan)throw Error('--private-vpn nicht zusammen mit --lan verwenden.');
  const tls=process.env.ALBO_TLS_KEY&&process.env.ALBO_TLS_CERT?{key:fs.readFileSync(process.env.ALBO_TLS_KEY),cert:fs.readFileSync(process.env.ALBO_TLS_CERT)}:undefined;
  const app=createWorkspaceServer({dataDir:process.env.ALBO_DATA_DIR||path.join(here,'data'),host:lan?'0.0.0.0':'127.0.0.1',port:Number(process.env.ALBO_PORT||8787),tls,allowInsecureLAN,vpnHost:privateVPN?process.env.ALBO_VPN_IP:undefined});
  const address=await app.listen();console.log(`ALBO Connect PC-Verwaltung: ${tls?'https':'http'}://localhost:${address.port}`);
  if(address.vpn)console.log(`Private Baustellenverbindung: http://${address.vpn.address}:${address.vpn.port} (nur bei aktiver VPN-Verbindung)`);
  if(process.argv.includes('--open')){
    const url=`${tls?'https':'http'}://localhost:${address.port}`;
    if(process.platform==='win32')spawn('rundll32.exe',['url.dll,FileProtocolHandler',url],{detached:true,stdio:'ignore',windowsHide:true}).unref();
    else if(process.platform==='darwin')spawn('open',[url],{detached:true,stdio:'ignore'}).unref();
  }
  if(lan&&!tls)console.log('Unverschlüsselter LAN-Test aktiviert. Nur in einem vertrauenswürdigen Testnetz verwenden.');
}
