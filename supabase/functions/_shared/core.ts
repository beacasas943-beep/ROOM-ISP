import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("ALLOWED_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
export const json = (body: unknown, status=200) => new Response(JSON.stringify(body), { status, headers:{...corsHeaders,"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store"} });
export const text = (body:string,status=200) => new Response(body,{status,headers:{"Content-Type":"text/plain; charset=utf-8","Cache-Control":"no-store"}});
export const options = (req:Request) => req.method === "OPTIONS" ? new Response("ok",{headers:corsHeaders}) : null;

export class HttpError extends Error { constructor(public status:number,message:string){super(message)} }
export function handleError(error:unknown){const known=error instanceof HttpError;console.error(known?error.message:"UNHANDLED",known?undefined:error);return json({ok:false,error:known?error.message:"INTERNAL_ERROR"},known?error.status:500)}
export function cleanText(v:unknown,max=180){return String(v??"").replace(/[\u0000-\u001f]/g," ").trim().slice(0,max)}
export function validUuid(v:unknown):v is string{return typeof v==="string"&&/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v)}
export function normalizePhone(v:unknown){let d=String(v??"").replace(/\D/g,"");if(d.startsWith("51")&&d.length===11)return `+${d}`;if(d.length===9)return `+51${d}`;if(d.length>=10&&d.length<=15)return `+${d}`;throw new HttpError(400,"PHONE_INVALID")}
export async function parseJson(req:Request,maxBytes=128_000){const size=Number(req.headers.get("content-length")||0);if(size>maxBytes)throw new HttpError(413,"PAYLOAD_TOO_LARGE");const raw=await req.text();if(raw.length>maxBytes)throw new HttpError(413,"PAYLOAD_TOO_LARGE");try{return JSON.parse(raw||"{}") as Record<string,any>}catch{throw new HttpError(400,"INVALID_JSON")}}
export function randomToken(bytes=32){const a=crypto.getRandomValues(new Uint8Array(bytes));return [...a].map(x=>x.toString(16).padStart(2,"0")).join("")}
export function randomReadable(length=12){const alphabet="ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";const bytes=crypto.getRandomValues(new Uint8Array(length));return [...bytes].map(x=>alphabet[x%alphabet.length]).join("")}
export async function sha256(v:string){const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v));return [...new Uint8Array(digest)].map(x=>x.toString(16).padStart(2,"0")).join("")}

export function adminClient():SupabaseClient{
  const url=Deno.env.get("SUPABASE_URL");
  let key=Deno.env.get("SUPABASE_SECRET_KEY")||Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(!key){
    try{const keys=JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS")||"{}");key=keys.default||Object.values(keys)[0]||""}catch{}
  }
  if(!url||!key)throw new Error("SERVER_CONFIGURATION_MISSING");
  return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
}
export async function requireUser(req:Request,db=adminClient()){
  const token=(req.headers.get("authorization")||"").replace(/^Bearer\s+/i,"");if(!token)throw new HttpError(401,"AUTH_REQUIRED");
  const {data,error}=await db.auth.getUser(token);if(error||!data.user)throw new HttpError(401,"INVALID_SESSION");return data.user;
}
export async function requireOrgAccess(db:SupabaseClient,userId:string,organizationId:string,roles:string[]=[]){
  const [{data:platform},{data:member},{data:org}]=await Promise.all([
    db.from("platform_admins").select("role,active").eq("user_id",userId).eq("active",true).maybeSingle(),
    db.from("organization_members").select("role,active").eq("organization_id",organizationId).eq("user_id",userId).eq("active",true).maybeSingle(),
    db.from("organizations").select("status").eq("id",organizationId).maybeSingle()
  ]);
  if(platform)return{platform:true,role:String(platform.role)};if(!org||!["TRIAL","ACTIVE"].includes(String(org.status)))throw new HttpError(403,"ORGANIZATION_NOT_ACTIVE");if(!member)throw new HttpError(403,"ORG_ACCESS_DENIED");if(roles.length&&!roles.includes(String(member.role)))throw new HttpError(403,"ROLE_NOT_ALLOWED");return{platform:false,role:String(member.role)};
}
export async function requirePlatformAdmin(db:SupabaseClient,userId:string){const {data}=await db.from("platform_admins").select("role").eq("user_id",userId).eq("active",true).maybeSingle();if(!data)throw new HttpError(403,"PLATFORM_ACCESS_DENIED");return data}
export async function requireCustomer(db:SupabaseClient,userId:string){const {data,error}=await db.from("customer_users").select("customer_id,customers!inner(id,organization_id,status,full_name,phone,organizations!inner(status,organization_settings(customer_portal_enabled)))").eq("user_id",userId).eq("active",true).maybeSingle();if(error||!data)throw new HttpError(403,"CUSTOMER_ACCESS_DENIED");const customer:any=Array.isArray(data.customers)?data.customers[0]:data.customers;const org:any=Array.isArray(customer.organizations)?customer.organizations[0]:customer.organizations;const settingsRaw:any=org?.organization_settings;const settings:any=Array.isArray(settingsRaw)?settingsRaw[0]:settingsRaw;if(customer.status!=="ACTIVE"||!["TRIAL","ACTIVE"].includes(String(org?.status))||settings?.customer_portal_enabled===false)throw new HttpError(403,"CUSTOMER_PORTAL_DISABLED");return{customer_id:data.customer_id,organization_id:customer.organization_id,customer}}
export async function requireRouter(req:Request,db=adminClient()){
  const bearer=(req.headers.get("authorization")||"").replace(/^Bearer\s+/i,"");if(bearer.length<32)throw new HttpError(401,"ROUTER_AUTH_REQUIRED");const tokenHash=await sha256(bearer);
  const {data:credential,error}=await db.from("router_credentials").select("id,router_id,expires_at,revoked_at,routers!inner(id,organization_id,status,sync_interval_seconds,last_seen_at)").eq("token_hash",tokenHash).is("revoked_at",null).maybeSingle();if(error||!credential)throw new HttpError(401,"INVALID_ROUTER_TOKEN");if(credential.expires_at&&new Date(credential.expires_at).getTime()<=Date.now())throw new HttpError(401,"ROUTER_TOKEN_EXPIRED");const router=Array.isArray(credential.routers)?credential.routers[0]:credential.routers;if(!router||router.status==="REVOKED")throw new HttpError(403,"ROUTER_REVOKED");return{credential,router} as const;
}
export async function audit(db:SupabaseClient,organizationId:string|null,userId:string|null,action:string,entityType:string,entityId?:string|null,afterData?:unknown){await db.from("audit_logs").insert({organization_id:organizationId,actor_user_id:userId,actor_type:userId?"USER":"SYSTEM",action,entity_type:entityType,entity_id:entityId||null,after_data:afterData??null})}

function cryptoKeyBytes(){const raw=Deno.env.get("INTEGRATION_CRYPTO_KEY");if(!raw||raw.length<32)throw new Error("INTEGRATION_CRYPTO_KEY_MISSING");if(/^[0-9a-f]{64}$/i.test(raw))return Uint8Array.from(raw.match(/../g)!.map(x=>parseInt(x,16)));try{const bin=atob(raw);const arr=Uint8Array.from(bin,c=>c.charCodeAt(0));if(arr.length===32)return arr}catch{}throw new Error("INTEGRATION_CRYPTO_KEY_INVALID")}
export async function encryptSecret(plain:string){const key=await crypto.subtle.importKey("raw",cryptoKeyBytes(),"AES-GCM",false,["encrypt"]);const iv=crypto.getRandomValues(new Uint8Array(12));const ct=new Uint8Array(await crypto.subtle.encrypt({name:"AES-GCM",iv},key,new TextEncoder().encode(plain)));return{ciphertext:btoa(String.fromCharCode(...ct)),iv:btoa(String.fromCharCode(...iv))}}
export async function decryptSecret(ciphertext:string,ivText:string){const key=await crypto.subtle.importKey("raw",cryptoKeyBytes(),"AES-GCM",false,["decrypt"]);const iv=Uint8Array.from(atob(ivText),c=>c.charCodeAt(0));const ct=Uint8Array.from(atob(ciphertext),c=>c.charCodeAt(0));const clear=await crypto.subtle.decrypt({name:"AES-GCM",iv},key,ct);return new TextDecoder().decode(clear)}
