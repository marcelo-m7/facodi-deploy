import { createHandler } from './handler.mjs';

const model = new Supabase.ai.Session('gte-small');

// Public, read-only function. PostgREST applies RLS under the publishable/anon key.
Deno.serve(createHandler({
  url: Deno.env.get('SUPABASE_URL'),
  anonKey: Deno.env.get('SUPABASE_ANON_KEY'),
}, fetch, async (query: string) => {
  return await model.run(query,{mean_pool:true,normalize:true});
}));
