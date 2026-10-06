-- =====================================================================
-- Te Ajudo a Votar · banco de dados
-- Como usar: Supabase > SQL Editor > New query > cole este arquivo > Run.
-- Pode rodar de novo sem problema: ele atualiza as funções.
-- =====================================================================

-- 1. Tabela com os pedidos e ofertas -----------------------------------
create table if not exists public.posts (
  id         uuid primary key default gen_random_uuid(),
  criado_em  timestamptz not null default now(),
  tipo       text not null check (tipo in ('pedido', 'oferta')),
  ajudas     text[] not null check (
               cardinality(ajudas) between 1 and 6
               and ajudas <@ array['companhia','local','duvidas','cuidar','acessibilidade','outro']),
  nome       text not null check (char_length(nome) between 1 and 40),
  uf         text not null check (uf in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA',
                                         'PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')),
  cidade     text not null check (char_length(cidade) between 2 and 60),
  bairro     text not null check (char_length(bairro) between 2 and 60),
  periodo    text not null check (periodo in ('manha', 'tarde', 'qualquer')),
  detalhes   text check (char_length(detalhes) <= 300),
  telefone   text not null check (telefone ~ '^[1-9][0-9]{9,10}$'),
  canais     text[] not null check (
               cardinality(canais) between 1 and 4
               and canais <@ array['ligacao','whatsapp','telegram','signal']),
  resolvido  boolean not null default false,
  oculto     boolean not null default false,   -- moderação: marque true para esconder
  denuncias  int not null default 0,
  contatos   int not null default 0,           -- quantas vezes alguém abriu o contato
  token      uuid not null default gen_random_uuid()  -- chave secreta de quem publicou
);

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

-- Lista o mural (sem telefone).
create or replace function public.listar(p_uf text default null)
returns table (
  id uuid, criado_em timestamptz, tipo text, ajudas text[], nome text, uf text,
  cidade text, bairro text, periodo text, detalhes text, canais text[], resolvido boolean
)
language sql stable security definer
set search_path = ''
as $$
  select p.id, p.criado_em, p.tipo, p.ajudas, p.nome, p.uf, p.cidade, p.bairro,
         p.periodo, p.detalhes, p.canais, p.resolvido
    from public.posts p
   where not p.oculto
     and (p_uf is null or p.uf = upper(p_uf))
   order by p.resolvido, p.criado_em desc
   limit 2000;
$$;

-- Publica um pedido ou oferta. Devolve o id e a chave secreta.
create or replace function public.criar(
  p_tipo text, p_ajudas text[], p_nome text, p_uf text, p_cidade text, p_bairro text,
  p_periodo text, p_detalhes text, p_telefone text, p_canais text[]
)
returns json
language plpgsql security definer
set search_path = ''
as $$
declare
  r public.posts;
  fone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
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
    insert into public.posts (tipo, ajudas, nome, uf, cidade, bairro, periodo, detalhes, telefone, canais)
    values (p_tipo, p_ajudas, btrim(p_nome), upper(btrim(p_uf)), btrim(p_cidade), btrim(p_bairro),
            p_periodo, nullif(btrim(coalesce(p_detalhes, '')), ''), fone, p_canais)
    returning * into r;
  exception when check_violation or not_null_violation then
    raise exception 'dados';
  end;

  return json_build_object('id', r.id, 'token', r.token, 'criado_em', r.criado_em);
end;
$$;

-- Mostra o telefone de um pedido/oferta (com limite por pessoa, contra robôs).
create or replace function public.ver_contato(p_id uuid)
returns json
language plpgsql security definer
set search_path = ''
as $$
declare
  t text;
  c text[];
begin
  perform public._limitar('contato', 60, interval '1 hour');
  update public.posts set contatos = contatos + 1
   where id = p_id and not oculto and not resolvido
  returning telefone, canais into t, c;
  if not found then
    raise exception 'nao_encontrado';
  end if;
  return json_build_object('telefone', t, 'canais', c);
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

-- Denúncia. Com 3 denúncias de pessoas diferentes, o post some do mural.
create or replace function public.denunciar(p_id uuid)
returns boolean
language plpgsql security definer
set search_path = ''
as $$
begin
  perform public._limitar('denunciar', 20, interval '1 hour');
  perform public._limitar('denunciar:' || p_id::text, 1, interval '1 day');
  update public.posts
     set denuncias = denuncias + 1,
         oculto = oculto or denuncias + 1 >= 3
   where id = p_id;
  return true;
end;
$$;

-- 4. Permissões -----------------------------------------------------------
revoke execute on function public._origem() from public, anon, authenticated;
revoke execute on function public._limitar(text, int, interval) from public, anon, authenticated;

revoke execute on function public.listar(text) from public;
revoke execute on function public.criar(text, text[], text, text, text, text, text, text, text, text[]) from public;
revoke execute on function public.ver_contato(uuid) from public;
revoke execute on function public.atualizar(uuid, uuid, boolean) from public;
revoke execute on function public.apagar(uuid, uuid) from public;
revoke execute on function public.denunciar(uuid) from public;

grant execute on function public.listar(text) to anon, authenticated;
grant execute on function public.criar(text, text[], text, text, text, text, text, text, text, text[]) to anon, authenticated;
grant execute on function public.ver_contato(uuid) to anon, authenticated;
grant execute on function public.atualizar(uuid, uuid, boolean) to anon, authenticated;
grant execute on function public.apagar(uuid, uuid) to anon, authenticated;
grant execute on function public.denunciar(uuid) to anon, authenticated;

-- 5. Depois da eleição ----------------------------------------------------
-- Em 26/10, apague tudo rodando estas duas linhas:
--   delete from public.posts;
--   delete from public.limites;
