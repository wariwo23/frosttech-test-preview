import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const INVITE_REDIRECT = "https://wariwo23.github.io/frosttech-test-preview/employee-accept-invitation-test.html";
const ALLOWED_ORIGIN = "https://wariwo23.github.io";

const corsHeaders = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function reply(status:number,body:Record<string,unknown>){
  return new Response(JSON.stringify(body),{status,headers:{...corsHeaders,"Content-Type":"application/json"}});
}
Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:corsHeaders});
  if(req.method!=="POST")return reply(405,{error:"Method not allowed"});
  if(!SUPABASE_URL||!SUPABASE_ANON_KEY||!SUPABASE_SERVICE_ROLE_KEY)
    return reply(500,{error:"Test server configuration is incomplete"});
  const authorization=req.headers.get("Authorization");
  if(!authorization?.startsWith("Bearer "))return reply(401,{error:"Please sign in as the test Super Administrator"});
  const token=authorization.substring(7);
  const callerClient=createClient(SUPABASE_URL,SUPABASE_ANON_KEY,{
    global:{headers:{Authorization:"Bearer "+token}},
    auth:{persistSession:false,autoRefreshToken:false}
  });
  const adminClient=createClient(SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,{
    auth:{persistSession:false,autoRefreshToken:false}
  });
  try{
    const {data:userData,error:userError}=await callerClient.auth.getUser();
    if(userError||!userData.user)return reply(401,{error:"Invalid test administrator session"});
    const actorUserId=userData.user.id;
    const {data:role,error:roleError}=await callerClient.rpc("admin_get_my_role");
    if(roleError||role!=="super_admin")return reply(403,{error:"Test Super Administrator access required"});
    const body=await req.json();
    const employeeId=body.employee_id;
    if(typeof employeeId!=="string"||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(employeeId))
      return reply(400,{error:"A valid employee ID is required"});
    const {data:employee,error:employeeError}=await adminClient.from("frosttech_employees")
      .select("id,full_name,email,department,employment_status,auth_user_id").eq("id",employeeId).single();
    if(employeeError||!employee)return reply(404,{error:"Employee record not found"});
    if(employee.employment_status!=="planned"||employee.auth_user_id!==null)
      return reply(409,{error:"This employee is not eligible for a new invitation"});
    const {data:invitation,error:inviteError}=await adminClient.auth.admin.inviteUserByEmail(employee.email,{
      redirectTo:INVITE_REDIRECT,
      data:{full_name:employee.full_name,account_type:"employee",frosttech_employee_id:employeeId}
    });
    if(inviteError||!invitation.user)return reply(400,{error:inviteError?.message??"Invitation could not be sent"});
    const invitedUserId=invitation.user.id;
    const {error:metadataError}=await adminClient.auth.admin.updateUserById(invitedUserId,{
      app_metadata:{...invitation.user.app_metadata,frosttech_account_type:"employee",frosttech_employee_id:employeeId}
    });
    if(metadataError){
      return reply(500,{error:"The test invitation email was sent, but account metadata setup needs recovery.",invitation_sent:true,employee_id:employeeId});
    }
    const {data:completed,error:completionError}=await adminClient.rpc("admin_complete_employee_invitation",{
      p_employee_id:employeeId,p_auth_user_id:invitedUserId,p_actor_user_id:actorUserId
    });
    if(completionError||completed!==true){
      return reply(500,{error:"The test invitation email was sent, but employee database linking needs recovery.",invitation_sent:true,employee_id:employeeId});
    }
    return reply(200,{success:true,message:"Test employee invitation sent successfully.",employee_id:employeeId,email:employee.email,employment_status:"invited"});
  }catch(error){
    return reply(500,{error:"An unexpected error occurred while processing the test invitation."});
  }
});