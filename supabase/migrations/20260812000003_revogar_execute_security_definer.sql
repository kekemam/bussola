-- ============================================================
-- Fechar as funções SECURITY DEFINER expostas via PostgREST.
-- Nenhuma delas deve ser chamável pela API:
--  · handle_new_user  -> corre por trigger em auth.users
--  · rls_auto_enable  -> corre por event trigger no DDL
--  · ai_recent_count  -> só o service_role (Edge Function)
-- Triggers e event triggers NÃO dependem do privilégio EXECUTE
-- do utilizador que despoleta a operação, por isso revogar é seguro.
--
-- Detetado por: supabase advisors (security) — lints 0028/0029.
-- ============================================================

revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.rls_auto_enable() from public, anon, authenticated;
revoke all on function public.ai_recent_count(uuid, int) from public, anon, authenticated;

-- garantir que a Edge Function continua a poder medir o rate limit
grant execute on function public.ai_recent_count(uuid, int) to service_role;
