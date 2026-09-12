import { adminClient, cleanText, handleError, HttpError, options, parseJson, requireRouter, sha256, text } from "../_shared/core.ts";

const ACCESS = new Set(["PPPOE","DHCP","STATIC","HOTSPOT"]);
const INVENTORY_TYPES = new Set(["SYSTEM","INTERFACE","IP_ADDRESS","ROUTE","IP_POOL","DHCP_SERVER","PPPOE_SERVER","HOTSPOT_SERVER","BRIDGE","VLAN","DNS","FIREWALL_SUMMARY"]);
const safe=(v:unknown,max=180)=>cleanText(v,max).replace(/[|\r\n]/g," ");
const bool=(v:unknown)=>v===true||v==="true"||v===1||v==="1";
const asNumber=(v:unknown)=>{const n=Number(String(v??"").replace(/[^0-9.-]/g,""));return Number.isFinite(n)?n:null};
async function fingerprint(value:unknown){return sha256(JSON.stringify(value));}

async function poll(db:any,auth:any,body:any){
  const router=auth.router; if(body.router_id&&body.router_id!==router.id)throw new HttpError(403,"ROUTER_ID_MISMATCH");
  const last=router.last_seen_at?new Date(router.last_seen_at).getTime():0;const shouldWrite=Date.now()-last>240000||router.status!=="ONLINE";
  if(shouldWrite){const health=body.health&&typeof body.health==="object"?body.health:{};await db.from("routers").update({status:"ONLINE",last_seen_at:new Date().toISOString(),health}).eq("id",router.id);await db.from("router_credentials").update({last_used_at:new Date().toISOString()}).eq("id",auth.credential.id)}
  const{data,error}=await db.rpc("lease_router_command",{p_router_id:router.id});if(error)throw error;const cmd=Array.isArray(data)?data[0]:data;if(!cmd)return text(`NONE|${Number(router.sync_interval_seconds||120)}`);
  const p=cmd.payload||{};
  const fields=[cmd.id,cmd.command_type,p.access_type||"",p.source_key||p.terminal_alias||"",p.router_profile||"",p.access_secret||"",p.rate_limit||"",p.duration_minutes||""];
  return text(`CMD|${fields.map(x=>safe(x,500)).join("|")}`);
}
async function result(db:any,auth:any,body:any){
  const cid=safe(body.command_id,80);if(!/^[0-9a-f-]{36}$/i.test(cid))throw new HttpError(400,"COMMAND_ID_INVALID");const{data:cmd}=await db.from("network_commands").select("*").eq("id",cid).eq("router_id",auth.router.id).maybeSingle();if(!cmd)throw new HttpError(404,"COMMAND_NOT_FOUND");if(cmd.status!=="LEASED")return text("OK|IGNORED");
  const success=bool(body.success),output=safe(body.result||body.output,4000);let payload=cmd.payload||{};
  if(success){
    const ack:any={output:output||"ok"};
    await db.from("network_commands").update({status:"ACK",acked_at:new Date().toISOString(),lease_until:null,ack_payload:ack,last_error:null,payload:cmd.command_type==="CREATE_ACCESS"?{...payload,access_secret:null}:payload}).eq("id",cid);
    if(cmd.service_id){let changes:any={};if(cmd.command_type==="CREATE_ACCESS"||cmd.command_type==="ENABLE")changes={status:"ACTIVE",suspended_at:null};else if(cmd.command_type==="SUSPEND")changes={status:"SUSPENDED",suspended_at:new Date().toISOString()};else if(cmd.command_type==="REMOVE_ACCESS")changes={status:"CANCELLED",cancelled_at:new Date().toISOString()};else if(cmd.command_type==="PLAN_CHANGE"&&payload.to_plan_id)changes={plan_id:payload.to_plan_id};if(Object.keys(changes).length)await db.from("services").update(changes).eq("id",cmd.service_id)}
    if(cmd.command_type==="PLAN_CHANGE"&&payload.request_id)await db.from("customer_requests").update({status:"COMPLETED"}).eq("id",payload.request_id).eq("status","APPROVED");
    return text("OK|ACK");
  }
  const attempts=Number(cmd.attempts||1),terminal=cmd.command_type==="TERMINAL_READ";const final=terminal||attempts>=Number(cmd.max_attempts||5);await db.from("network_commands").update({status:final?"FAILED":"QUEUED",lease_until:null,available_at:new Date(Date.now()+(final?0:Math.min(15,attempts*2))*60000).toISOString(),last_error:output||"router_rejected",ack_payload:terminal?{output:output||"router_rejected"}:null}).eq("id",cid);return text(`OK|${final?"FAILED":"RETRY"}`);
}
async function inventory(db:any,auth:any,body:any){
  const router=auth.router;if(body.router_id&&body.router_id!==router.id)throw new HttpError(403,"ROUTER_ID_MISMATCH");const items=Array.isArray(body.items)?body.items:[];if(items.length>120)throw new HttpError(413,"INVENTORY_BATCH_TOO_LARGE");let changed=0;
  for(const raw of items){if(!raw||typeof raw!=="object")continue;const type=safe(raw.type,40).toUpperCase(),key=safe(raw.key,220);if(!type||!key)continue;
    if(type==="PROFILE"){
      const data={rate_limit:safe(raw.rate_limit,120)||null,local_address:safe(raw.local_address,100)||null,remote_address:safe(raw.remote_address,100)||null,only_one:safe(raw.only_one,20)||null};const fp=await fingerprint(data);const{data:old}=await db.from("router_profiles").select("fingerprint").eq("router_id",router.id).eq("name",key).maybeSingle();if(old?.fingerprint===fp){await db.from("router_profiles").update({last_seen_at:new Date().toISOString()}).eq("router_id",router.id).eq("name",key)}else{await db.from("router_profiles").upsert({organization_id:router.organization_id,router_id:router.id,name:key,...data,fingerprint:fp,last_seen_at:new Date().toISOString()},{onConflict:"router_id,name"});changed++}continue;
    }
    if(ACCESS.has(type)){
      const meta={hostname:safe(raw.hostname,160)||null,server:safe(raw.server,120)||null,queue:safe(raw.queue,120)||null,target:safe(raw.target,160)||null,max_limit:safe(raw.max_limit,120)||null,disabled:String(raw.disabled??"")};const data={display_name:safe(raw.name,180)||key,comment:safe(raw.comment,300)||null,mac_address:safe(raw.caller_id||raw.mac,40)||null,ip_address:safe(raw.ip,80)||null,router_profile:safe(raw.profile,120)||null,metadata:meta};const fp=await fingerprint(data);const{data:old}=await db.from("router_observations").select("fingerprint,state").eq("router_id",router.id).eq("source_type",type).eq("source_key",key).maybeSingle();const row:any={organization_id:router.organization_id,router_id:router.id,source_type:type,source_key:key,...data,fingerprint:fp,last_seen_at:new Date().toISOString()};if(data.ip_address&&!/^([0-9a-f:.]+)(\/\d+)?$/i.test(data.ip_address))row.ip_address=null;if(old?.fingerprint===fp){await db.from("router_observations").update({last_seen_at:row.last_seen_at}).eq("router_id",router.id).eq("source_type",type).eq("source_key",key)}else{await db.from("router_observations").upsert(row,{onConflict:"router_id,source_type,source_key"});changed++}continue;
    }
    if(INVENTORY_TYPES.has(type)){
      const data={...raw};delete data.type;delete data.key;for(const k of Object.keys(data))if(typeof data[k]==="string")data[k]=safe(data[k],500);const fp=await fingerprint(data);const{data:old}=await db.from("router_inventory_items").select("fingerprint").eq("router_id",router.id).eq("item_type",type).eq("item_key",key).maybeSingle();if(old?.fingerprint===fp){await db.from("router_inventory_items").update({last_seen_at:new Date().toISOString()}).eq("router_id",router.id).eq("item_type",type).eq("item_key",key)}else{await db.from("router_inventory_items").upsert({organization_id:router.organization_id,router_id:router.id,item_type:type,item_key:key,data,fingerprint:fp,last_seen_at:new Date().toISOString()},{onConflict:"router_id,item_type,item_key"});changed++}
    }
  }
  if(bool(body.final)){await db.from("routers").update({last_inventory_at:new Date().toISOString(),last_seen_at:new Date().toISOString(),status:"ONLINE"}).eq("id",router.id)}
  return text(`OK|${changed}`);
}

Deno.serve(async(req:Request)=>{const pre=options(req);if(pre)return pre;if(req.method!=="POST")return text("METHOD_NOT_ALLOWED",405);try{const db=adminClient(),auth=await requireRouter(req,db),body=await parseJson(req,300_000);if(Number(body.protocol||0)!==4)throw new HttpError(426,"CONNECTOR_PROTOCOL_UNSUPPORTED");const mode=safe(body.mode,20);if(mode==="poll")return await poll(db,auth,body);if(mode==="result")return await result(db,auth,body);if(mode==="inventory")return await inventory(db,auth,body);throw new HttpError(400,"MODE_INVALID")}catch(e){const res=handleError(e);const parsed=await res.json().catch(()=>({error:"INTERNAL_ERROR"}));return text(`ERR|${safe(parsed.error,120)}`,res.status)}});
