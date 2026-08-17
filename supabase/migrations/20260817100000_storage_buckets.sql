-- ============================================================
-- KEVIMA — armazenamento de ficheiros
--
-- Três baldes com posturas diferentes, porque o risco é diferente:
--
--  · avatars    fotografias de perfil — públicas, pequenas
--  · empresas   logótipos e imagens de anúncios — públicas
--  · documentos comprovativos para verificação — PRIVADOS
--
-- O terceiro é o que exige mais cuidado: guarda documentos de
-- identidade de pessoas em situação vulnerável. Nunca é público, o
-- acesso é do titular e da administração, e os tipos aceites são
-- restritos para não servir de depósito de ficheiros arbitrários.
--
-- Convenção de caminhos: a primeira pasta é o dono.
--   avatars/{user_id}/foto.jpg
--   empresas/{company_id}/logo.png
--   documentos/{user_id}/cedula.pdf
-- As políticas comparam essa pasta com quem está a pedir, por isso
-- ninguém escreve na pasta de outra pessoa.
--
-- NOTA RGPD: não há cascata de auth.users para storage. Apagar a
-- conta NÃO apaga os ficheiros — é a app que os remove primeiro,
-- em apagarFicheiros(), antes de terminar a sessão.
-- ============================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars','avatars', true, 2097152,
   array['image/jpeg','image/png','image/webp']),
  ('empresas','empresas', true, 5242880,
   array['image/jpeg','image/png','image/webp','image/avif']),
  ('documentos','documentos', false, 10485760,
   array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------- avatars ----------
create policy "avatar_leitura_publica" on storage.objects
  for select to anon, authenticated using (bucket_id = 'avatars');

create policy "avatar_dono_escreve" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "avatar_dono_actualiza" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "avatar_dono_apaga" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------- empresas ----------
create policy "empresa_imagens_publicas" on storage.objects
  for select to anon, authenticated using (bucket_id = 'empresas');

create policy "empresa_membros_escrevem" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'empresas' and (storage.foldername(name))[1] in (
      select m.company_id::text from public.company_members m where m.user_id = (select auth.uid())));

create policy "empresa_membros_actualizam" on storage.objects
  for update to authenticated
  using (bucket_id = 'empresas' and (storage.foldername(name))[1] in (
      select m.company_id::text from public.company_members m where m.user_id = (select auth.uid())))
  with check (bucket_id = 'empresas' and (storage.foldername(name))[1] in (
      select m.company_id::text from public.company_members m where m.user_id = (select auth.uid())));

create policy "empresa_membros_apagam" on storage.objects
  for delete to authenticated
  using (bucket_id = 'empresas' and (storage.foldername(name))[1] in (
      select m.company_id::text from public.company_members m where m.user_id = (select auth.uid())));

-- ---------- documentos (privado) ----------
-- Sem política para `anon`: quem não tem sessão não lê nada.
create policy "documento_titular_le" on storage.objects
  for select to authenticated
  using (bucket_id = 'documentos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "documento_admin_le" on storage.objects
  for select to authenticated
  using (bucket_id = 'documentos'
    and exists (select 1 from public.platform_admins a where a.user_id = (select auth.uid())));

create policy "documento_titular_envia" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'documentos' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "documento_titular_apaga" on storage.objects
  for delete to authenticated
  using (bucket_id = 'documentos' and (storage.foldername(name))[1] = (select auth.uid())::text);
