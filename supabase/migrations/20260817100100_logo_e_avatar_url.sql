-- Endereço da imagem de perfil. Guardamos o URL público e não o
-- ficheiro: o balde `avatars` é público, por isso o URL é estável e
-- evita uma chamada ao Storage sempre que se desenha um cartão.
alter table public.companies add column if not exists logo_url text;
alter table public.profiles  add column if not exists avatar_url text;

comment on column public.companies.logo_url is 'URL público em storage/avatars ou /empresas.';
comment on column public.profiles.avatar_url is 'URL público em storage/avatars.';
