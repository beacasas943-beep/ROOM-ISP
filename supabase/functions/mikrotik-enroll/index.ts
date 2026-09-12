import { adminClient, cleanText, handleError, HttpError, json, options, parseJson, randomToken, sha256, text } from "../_shared/core.ts";

Deno.serve(async(req:Request)=>{
  const pre=options(req);if(pre)return pre;if(req.method!=="POST")return json({ok:false,error:"METHOD_NOT_ALLOWED"},405);
  try{
    const db=adminClient(),body=await parseJson(req,64_000);
    if(Number(body.protocol||0)!==4)throw new HttpError(426,"CONNECTOR_PROTOCOL_UNSUPPORTED");
    const code=cleanText(body.enrollment_code,200);if(code.length<40)throw new HttpError(400,"ENROLLMENT_CODE_INVALID");
    const agentToken=randomToken(32),agentHash=await sha256(agentToken),enrollmentHash=await sha256(code),prefix=agentToken.slice(0,10);
    const d=(body.device&&typeof body.device==="object")?body.device:body;
    const device={
      name:cleanText(d.identity||d.name,100)||"MikroTik",
      identity:cleanText(d.identity,100)||null,
      model:cleanText(d.model,120)||null,
      serial_number:cleanText(d.serial_number,120)||null,
      software_id:cleanText(d.software_id,120)||null,
      routeros_version:cleanText(d.routeros_version,80)||null,
      architecture:cleanText(d.architecture,80)||null,
      device_key:cleanText(d.device_key||d.software_id,180)||null,
      connector_version:cleanText(d.connector_version||body.connector_version,40)||"4",
    };
    const capabilities=body.capabilities&&typeof body.capabilities==="object"?body.capabilities:{};
    const{data,error}=await db.rpc("claim_router_enrollment",{p_enrollment_hash:enrollmentHash,p_agent_hash:agentHash,p_token_prefix:prefix,p_device:device,p_capabilities:capabilities});if(error){console.error(error);throw new HttpError(400,"ENROLLMENT_REJECTED")}
    const row=Array.isArray(data)?data[0]:data;if(!row?.router_id)throw new HttpError(400,"ENROLLMENT_REJECTED");
    return text(`OK|${row.router_id}|${agentToken}|2`);
  }catch(e){return handleError(e)}
});
