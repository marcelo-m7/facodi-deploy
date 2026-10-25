import {createIngestionHandler} from './handler.mjs';

// Internal-only endpoint: requires service-role JWT AND exact service key.
Deno.serve(createIngestionHandler({
  url:Deno.env.get('SUPABASE_URL'),
  serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
}));
