import {createIndexerHandler} from './handler.mjs';

const model = new Supabase.ai.Session('gte-small');
Deno.serve(createIndexerHandler({
  url:Deno.env.get('SUPABASE_URL'),
  serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
}, fetch, async (content:string)=>await model.run(content,{mean_pool:true,normalize:true})));
