import { createHandler } from './handler.mjs';

// Public, read-only function. PostgREST applies RLS under the publishable/anon key.
Deno.serve(createHandler({
  url: Deno.env.get('SUPABASE_URL'),
  anonKey: Deno.env.get('SUPABASE_ANON_KEY'),
}));
