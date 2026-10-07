-- =====================================================================
-- Te Ajudo a Votar · banco de dados
-- Como usar: Supabase > SQL Editor > New query > cole este arquivo > Run.
-- Pode rodar de novo sem problema: ele atualiza a tabela e as funções.
-- =====================================================================

-- 1. Tabela com os pedidos e ofertas -----------------------------------
create table if not exists public.posts (
  id         uuid primary key default gen_random_uuid(),
  criado_em  timestamptz not null default now(),
  tipo       text not null check (tipo in ('pedido', 'oferta')),
  nome       text not null check (char_length(nome) between 1 and 40),
  uf         text not null check (uf in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA',
                                         'PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')),
  cidade     text not null check (char_length(cidade) between 2 and 60),
  bairro     text check (bairro is null or char_length(bairro) between 2 and 60),
  detalhes   text check (detalhes is null or char_length(detalhes) <= 300),
  telefone   text check (telefone is null or telefone ~ '^[1-9][0-9]{9,10}$'),
  instagram  text check (instagram is null or instagram ~ '^[A-Za-z0-9._]{1,30}$'),
  resolvido  boolean not null default false,
  oculto     boolean not null default false,   -- moderação: marque true para esconder
  denuncias  int not null default 0,
  contatos   int not null default 0,           -- quantas vezes alguém abriu o contato
  token      uuid not null default gen_random_uuid(),  -- chave secreta de quem publicou
  constraint posts_contato_check check (telefone is not null or instagram is not null)
);

-- Atualiza um banco criado com a versão anterior do site (sem efeito num banco novo).
alter table public.posts add column if not exists instagram text;
alter table public.posts alter column telefone drop not null;
alter table public.posts alter column bairro drop not null;
alter table public.posts drop column if exists ajudas;
alter table public.posts drop column if exists periodo;
alter table public.posts drop column if exists canais;
alter table public.posts drop constraint if exists posts_bairro_check;
alter table public.posts add constraint posts_bairro_check check (bairro is null or char_length(bairro) between 2 and 60);
alter table public.posts drop constraint if exists posts_detalhes_check;
alter table public.posts add constraint posts_detalhes_check check (detalhes is null or char_length(detalhes) <= 300);
alter table public.posts drop constraint if exists posts_telefone_check;
alter table public.posts add constraint posts_telefone_check check (telefone is null or telefone ~ '^[1-9][0-9]{9,10}$');
alter table public.posts drop constraint if exists posts_instagram_check;
alter table public.posts add constraint posts_instagram_check check (instagram is null or instagram ~ '^[A-Za-z0-9._]{1,30}$');
alter table public.posts drop constraint if exists posts_contato_check;
alter table public.posts add constraint posts_contato_check check (telefone is not null or instagram is not null);

create index if not exists posts_uf_idx on public.posts (uf, criado_em desc);

-- Ninguém de fora acessa a tabela direto. Tudo passa pelas funções abaixo.
alter table public.posts enable row level security;
revoke all on table public.posts from anon, authenticated;

-- 2. Controle anti-spam (guarda só um código do IP, nunca o IP) ----------
create table if not exists public.limites (
  chave text not null,
  acao  text not null,
  em    timestamptz not null default now()
);
create index if not exists limites_idx on public.limites (chave, acao, em);
alter table public.limites enable row level security;
revoke all on table public.limites from anon, authenticated;

create or replace function public._origem()
returns text
language sql stable
set search_path = ''
as $$
  with h as (select nullif(current_setting('request.headers', true), '')::json as j)
  select case when ip is null then null
              else encode(sha256(convert_to(ip || ':teajudoavotar', 'UTF8')), 'hex') end
  from (
    select coalesce(
             nullif(btrim(j->>'cf-connecting-ip'), ''),
             nullif(btrim(split_part(j->>'x-forwarded-for', ',', 1)), '')
           ) as ip
    from h
  ) s;
$$;

create or replace function public._limitar(p_acao text, p_max int, p_janela interval)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  k text := public._origem();
  n int;
begin
  if k is null then return; end if;
  select count(*) into n from public.limites
   where chave = k and acao = p_acao and em > now() - p_janela;
  if n >= p_max then
    raise exception 'limite';
  end if;
  insert into public.limites (chave, acao) values (k, p_acao);
end;
$$;

-- 3. Funções públicas que o site usa -------------------------------------

-- Versões antigas (assinatura ou retorno diferentes) saem antes de criar as novas.
drop function if exists public.listar(text);
drop function if exists public.criar(text, text[], text, text, text, text, text, text, text, text[]);
drop function if exists public.criar(text, text, text, text, text, text, text, text);

-- Lista o mural (sem telefone nem instagram; só diz quais canais existem).
create function public.listar(p_uf text default null)
returns table (
  id uuid, criado_em timestamptz, tipo text, nome text, uf text,
  cidade text, bairro text, detalhes text, canais text[], resolvido boolean
)
language sql stable security definer
set search_path = ''
as $$
  select p.id, p.criado_em, p.tipo, p.nome, p.uf, p.cidade, p.bairro, p.detalhes,
         array_remove(array[
           case when p.telefone is not null then 'whatsapp' end,
           case when p.instagram is not null then 'instagram' end
         ], null) as canais,
         p.resolvido
    from public.posts p
   where not p.oculto
     and (p_uf is null or p.uf = upper(p_uf))
   order by p.resolvido, p.criado_em desc
   limit 2000;
$$;

-- Publica um pedido ou oferta. Devolve o id e a chave secreta.
create function public.criar(
  p_tipo text, p_nome text, p_uf text, p_cidade text, p_bairro text,
  p_detalhes text, p_telefone text, p_instagram text
)
returns json
language plpgsql security definer
set search_path = ''
as $$
declare
  r public.posts;
  fone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  insta text := regexp_replace(btrim(coalesce(p_instagram, '')), '^@+', '');
begin
  if now() > timestamptz '2026-10-25 17:00:00-03' then
    raise exception 'encerrado';
  end if;
  if char_length(fone) in (12, 13) and left(fone, 2) = '55' then
    fone := substr(fone, 3);
  end if;
  fone := regexp_replace(fone, '^0', '');

  perform public._limitar('criar', 6, interval '1 hour');
  delete from public.limites where em < now() - interval '1 day';

  begin
    insert into public.posts (tipo, nome, uf, cidade, bairro, detalhes, telefone, instagram)
    values (p_tipo, btrim(p_nome), upper(btrim(p_uf)), btrim(p_cidade),
            nullif(btrim(coalesce(p_bairro, '')), ''),
            nullif(btrim(coalesce(p_detalhes, '')), ''),
            nullif(fone, ''), nullif(insta, ''))
    returning * into r;
  exception when check_violation or not_null_violation then
    raise exception 'dados';
  end;

  return json_build_object('id', r.id, 'token', r.token, 'criado_em', r.criado_em);
end;
$$;

-- Mostra o contato de um pedido/oferta (com limite por pessoa, contra robôs).
create or replace function public.ver_contato(p_id uuid)
returns json
language plpgsql security definer
set search_path = ''
as $$
declare
  t text;
  i text;
begin
  perform public._limitar('contato', 60, interval '1 hour');
  update public.posts set contatos = contatos + 1
   where id = p_id and not oculto and not resolvido
  returning telefone, instagram into t, i;
  if not found then
    raise exception 'nao_encontrado';
  end if;
  return json_build_object('telefone', t, 'instagram', i);
end;
$$;

-- Marca como resolvido (ou reabre). Precisa da chave secreta.
create or replace function public.atualizar(p_id uuid, p_token uuid, p_resolvido boolean)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
begin
  update public.posts set resolvido = p_resolvido where id = p_id and token = p_token;
  if not found then
    raise exception 'nao_encontrado';
  end if;
  return true;
end;
$$;

-- Apaga de vez. Precisa da chave secreta.
create or replace function public.apagar(p_id uuid, p_token uuid)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
begin
  delete from public.posts where id = p_id and token = p_token;
  if not found then
    raise exception 'nao_encontrado';
  end if;
  return true;
end;
$$;

-- Denúncia: só registra e conta. Esconder um anúncio é decisão humana (coluna oculto).
-- Um limite automático (ex.: 3 denúncias) seria alvo fácil de ataque coordenado contra anúncios legítimos.
create or replace function public.denunciar(p_id uuid)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
begin
  perform public._limitar('denunciar', 20, interval '1 hour');
  perform public._limitar('denunciar:' || p_id::text, 1, interval '1 day');
  update public.posts set denuncias = denuncias + 1 where id = p_id;
  return true;
end;
$$;

-- 4. Permissões -----------------------------------------------------------
revoke execute on function public._origem() from public, anon, authenticated;
revoke execute on function public._limitar(text, int, interval) from public, anon, authenticated;

revoke execute on function public.listar(text) from public;
revoke execute on function public.criar(text, text, text, text, text, text, text, text) from public;
revoke execute on function public.ver_contato(uuid) from public;
revoke execute on function public.atualizar(uuid, uuid, boolean) from public;
revoke execute on function public.apagar(uuid, uuid) from public;
revoke execute on function public.denunciar(uuid) from public;

grant execute on function public.listar(text) to anon, authenticated;
grant execute on function public.criar(text, text, text, text, text, text, text, text) to anon, authenticated;
grant execute on function public.ver_contato(uuid) to anon, authenticated;
grant execute on function public.atualizar(uuid, uuid, boolean) to anon, authenticated;
grant execute on function public.apagar(uuid, uuid) to anon, authenticated;
grant execute on function public.denunciar(uuid) to anon, authenticated;

-- Avisa o PostgREST que o esquema mudou (o Supabase costuma fazer isso sozinho).
notify pgrst, 'reload schema';

-- 5. Moderação (painel admin.html) ---------------------------------------
-- A senha do painel fica guardada só como hash. Para trocar a senha, rode:
--   update public.admin_config set segredo_hash = encode(sha256(convert_to('SUA-NOVA-SENHA', 'UTF8')), 'hex'), atualizado_em = now() where id = 1;
create table if not exists public.admin_config (
  id int primary key default 1 check (id = 1),
  segredo_hash text not null,
  atualizado_em timestamptz not null default now()
);
alter table public.admin_config enable row level security;
revoke all on table public.admin_config from anon, authenticated;
-- Num banco novo, defina a senha inicial trocando o hash abaixo (este é um valor de exemplo, não funciona):
insert into public.admin_config (id, segredo_hash) values (1, 'troque-este-hash')
  on conflict (id) do nothing;

create or replace function public._admin_ok(p_segredo text)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare h text;
begin
  select segredo_hash into h from public.admin_config where id = 1;
  if h is null or p_segredo is null or encode(sha256(convert_to(p_segredo, 'UTF8')), 'hex') <> h then
    perform public._limitar('admin_falha', 10, interval '1 hour');
    raise exception 'nao_autorizado';
  end if;
end;
$$;

-- Lista tudo, inclusive escondidos, com contato. Só com a senha.
create or replace function public.admin_listar(p_segredo text)
returns table (
  id uuid, criado_em timestamptz, tipo text, nome text, uf text, cidade text, bairro text, detalhes text,
  telefone text, instagram text, resolvido boolean, oculto boolean, denuncias int, contatos int
)
language plpgsql security definer
set search_path = ''
as $$
begin
  perform public._admin_ok(p_segredo);
  return query
    select p.id, p.criado_em, p.tipo, p.nome, p.uf, p.cidade, p.bairro, p.detalhes, p.telefone, p.instagram,
           p.resolvido, p.oculto, p.denuncias, p.contatos
      from public.posts p
     order by p.denuncias desc, p.criado_em desc
     limit 5000;
end;
$$;

-- Ações: ocultar, mostrar, zerar (denúncias), resolver, reabrir, apagar.
create or replace function public.admin_moderar(p_segredo text, p_id uuid, p_acao text)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
declare t uuid;
begin
  perform public._admin_ok(p_segredo);
  if p_acao = 'ocultar' then update public.posts set oculto = true where id = p_id;
  elsif p_acao = 'mostrar' then update public.posts set oculto = false where id = p_id;
  elsif p_acao = 'zerar' then update public.posts set denuncias = 0 where id = p_id;
  elsif p_acao = 'resolver' then update public.posts set resolvido = true where id = p_id;
  elsif p_acao = 'reabrir' then update public.posts set resolvido = false where id = p_id;
  elsif p_acao = 'apagar' then
    select token into t from public.posts where id = p_id;
    if t is null then raise exception 'nao_encontrado'; end if;
    perform public.apagar(p_id, t);
  else
    raise exception 'dados';
  end if;
  if not found then raise exception 'nao_encontrado'; end if;
  return true;
end;
$$;

revoke execute on function public._admin_ok(text) from public, anon, authenticated;
revoke execute on function public.admin_listar(text) from public;
revoke execute on function public.admin_moderar(text, uuid, text) from public;
grant execute on function public.admin_listar(text) to anon, authenticated;
grant execute on function public.admin_moderar(text, uuid, text) to anon, authenticated;

-- 6. Depois da eleição ----------------------------------------------------
-- Em 26/10, apague tudo rodando estas duas linhas:
--   delete from public.posts;
--   delete from public.limites;
