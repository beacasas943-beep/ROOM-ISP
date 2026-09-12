import { adminClient, audit, cleanText, handleError, HttpError, json, options, parseJson, randomToken, requireOrgAccess, requireUser, sha256, validUuid } from "../_shared/core.ts";

Deno.serve(async(req:Request)=>{
  const pre=options(req);if(pre)return pre;if(req.method!=="POST")return json({ok:false,error:"METHOD_NOT_ALLOWED"},405);
  try{
    const db=adminClient(),user=await requireUser(req,db),body=await parseJson(req);
    const oid=body.organization_id;if(!validUuid(oid))throw new HttpError(400,"ORGANIZATION_ID_INVALID");
    await requireOrgAccess(db,user.id,oid,["OWNER","ADMIN","TECHNICIAN"]);
    const {data:org}=await db.from("organizations").select("id,status,router_limit").eq("id",oid).single();
    if(!org||["PAUSED","CANCELLED"].includes(org.status))throw new HttpError(403,"ORGANIZATION_NOT_ACTIVE");
    const {count}=await db.from("routers").select("id",{count:"exact",head:true}).eq("organization_id",oid).neq("status","REVOKED");
    if(Number(count||0)>=Number(org.router_limit||3))throw new HttpError(409,"ROUTER_LIMIT_REACHED");
    const code=randomToken(32),hash=await sha256(code),expires=new Date(Date.now()+20*60*1000).toISOString();
    const{data,error}=await db.from("router_enrollment_tokens").insert({organization_id:oid,token_hash:hash,label:cleanText(body.label,80)||"MikroTik",expires_at:expires,created_by:user.id}).select("id").single();if(error)throw error;
    const base=Deno.env.get("SUPABASE_URL");if(!base)throw new Error("SUPABASE_URL_MISSING");
    await audit(db,oid,user.id,"ROUTER_ENROLLMENT_ISSUED","router_enrollment",data.id,{expires_at:expires});
    return json({ok:true,enrollment_code:code,expires_at:expires,enroll_url:`${base}/functions/v1/mikrotik-enroll`,agent_url:`${base}/functions/v1/mikrotik-agent`});
  }catch(e){return handleError(e)}
});
