-- Read-only snapshot of what is in a Supabase project's public schema.
-- Run it in the SQL Editor and export the result as CSV. It changes nothing.
-- Kinds: function (definition and who may run it), column (table columns), rows (row counts).
select 'function' as kind, p.proname::text as name, pg_get_functiondef(p.oid) as definition, p.proacl::text as acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
union all
select 'column', c.table_name || '.' || c.column_name,
       c.data_type || ', nullable=' || c.is_nullable || ', default=' || coalesce(c.column_default, ''), null
from information_schema.columns c
where c.table_schema = 'public'
union all
select 'rows', 'trips', count(*)::text, null from public.trips
union all
select 'rows', 'cars', count(*)::text, null from public.cars
order by 1, 2;
