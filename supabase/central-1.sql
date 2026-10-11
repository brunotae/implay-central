-- =====================================================================
-- Implay Central · banco (versão 1)
-- Roda no MESMO projeto do Supabase do Implay Despesas (Implay-despesas).
-- Cole tudo em: SQL Editor > New query > Run. Pode rodar mais de uma vez.
--
-- O que faz:
-- • Novo nível de acesso "seller" (hosts, operadores, editores).
--   Seller NÃO enxerga despesas, reembolsos nem dados de outros freelancers.
-- • Tabelas da Central: marcas, jobs, propostas, freelancers, lives,
--   candidaturas (registro de escolha livre), pagamentos de freelancer,
--   recebimentos das marcas, recados e histórico da Central.
-- =====================================================================

-- ---------- 1. Nível "seller" ----------
alter table public.profiles drop constraint if exists profiles_nivel_check;
alter table public.profiles add constraint profiles_nivel_check check (nivel in ('adm','manager','basic','seller'));
alter table public.convites drop constraint if exists convites_nivel_check;
alter table public.convites add constraint convites_nivel_check check (nivel in ('adm','manager','basic','seller'));

-- Sócios e equipe interna (tudo menos seller)
create or replace function public.sou_interno() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'ativo' and nivel in ('adm','manager','basic'))
$$;
-- Quem opera (cria e edita): ADM e Gerência
create or replace function public.pode_operar() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'ativo' and nivel in ('adm','manager'))
$$;

-- Despesas, reembolsos e histórico do Despesas: só equipe interna (seller fora)
drop policy if exists p_desp_ver on public.despesas;
create policy p_desp_ver on public.despesas for select using (public.sou_interno());
drop policy if exists p_reemb_ver on public.reembolsos;
create policy p_reemb_ver on public.reembolsos for select using (public.sou_interno());
drop policy if exists p_hist_ver on public.historico;
create policy p_hist_ver on public.historico for select using (public.sou_interno());
drop policy if exists p_convites_ver on public.convites;
create policy p_convites_ver on public.convites for select using (public.sou_interno());
drop policy if exists p_profiles_ver on public.profiles;
create policy p_profiles_ver on public.profiles for select using (id = auth.uid() or public.sou_interno());
drop policy if exists p_comp_ver on storage.objects;
create policy p_comp_ver on storage.objects for select using (bucket_id = 'comprovantes' and public.sou_interno());

create or replace function public.log_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status <> old.status then
    insert into historico (quem, acao) values (auth.uid(),
      case new.status when 'ativo' then 'liberou o acesso de ' when 'bloqueado' then 'bloqueou o acesso de ' else 'mudou para pendente o acesso de ' end || new.nome);
  end if;
  if new.nivel <> old.nivel then
    insert into historico (quem, acao) values (auth.uid(), 'mudou o nível de ' || new.nome || ' para ' ||
      case new.nivel when 'adm' then 'ADM' when 'manager' then 'Gerência' when 'seller' then 'Seller' else 'Consulta' end);
  end if;
  return new;
end $$;

-- ---------- 2. Tabelas ----------
create table if not exists public.marcas (
  id            uuid primary key default gen_random_uuid(),
  nome          text not null check (btrim(nome) <> ''),
  segmento      text not null default '',
  cor           text not null default '#2B3BFF',
  contato_nome  text not null default '',
  contato_tel   text not null default '',
  conta_propria boolean not null default false,
  ativo         boolean not null default true,
  obs           text not null default '',
  criado_por    uuid default auth.uid() references public.profiles(id),
  criado_em     timestamptz not null default now()
);

create table if not exists public.jobs (
  id              uuid primary key default gen_random_uuid(),
  marca_id        uuid not null references public.marcas(id),
  nome            text not null check (btrim(nome) <> ''),
  etapa           smallint not null default 0 check (etapa between 0 and 8),
  responsavel_id  uuid references public.profiles(id),
  valor           numeric(12,2) not null default 0,
  lives_previstas int not null default 0,
  canais          text not null default '',
  prox_passo      text not null default '',
  prox_data       date,
  alerta          text not null default '' check (alerta in ('','atencao','travado')),
  obs             text not null default '',
  status          text not null default 'ativo' check (status in ('ativo','cancelado')),
  criado_por      uuid default auth.uid() references public.profiles(id),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);

create sequence if not exists public.propostas_numero_seq start 1;
create table if not exists public.propostas (
  id          uuid primary key default gen_random_uuid(),
  numero      int not null default nextval('public.propostas_numero_seq'),
  marca_id    uuid not null references public.marcas(id),
  job_id      uuid references public.jobs(id),
  escopo      text not null default '',
  valor       numeric(12,2) not null default 0,
  status      text not null default 'rascunho' check (status in ('rascunho','enviada','negociacao','aceita','perdida')),
  validade    date,
  motivo      text not null default '',
  criado_por  uuid default auth.uid() references public.profiles(id),
  criado_em   timestamptz not null default now()
);

create table if not exists public.freelancers (
  id           uuid primary key default gen_random_uuid(),
  nome         text not null check (btrim(nome) <> ''),
  papel        text not null default 'host' check (papel in ('host','operador','editor','outro')),
  email        text not null default '',
  telefone     text not null default '',
  pix          text not null default '',
  documento    text not null default '',
  valor_hora   numeric(10,2) not null default 0,
  valor_corte  numeric(10,2) not null default 0,
  ativo        boolean not null default true,
  obs          text not null default '',
  criado_em    timestamptz not null default now()
);

create table if not exists public.lives (
  id                uuid primary key default gen_random_uuid(),
  job_id            uuid references public.jobs(id),
  marca_id          uuid not null references public.marcas(id),
  data              date not null,
  ini               time not null,
  fim               time not null,
  sala              text not null default '',
  local             text not null default 'paulista' check (local in ('paulista','cliente')),
  conta             text not null default 'marca' check (conta in ('marca','implay')),
  status            text not null default 'agendada' check (status in ('agendada','aovivo','feita','cancelada')),
  precisa_host      boolean not null default true,
  precisa_operador  boolean not null default true,
  host_id           uuid references public.freelancers(id),
  operador_id       uuid references public.freelancers(id),
  gmv               numeric(12,2),
  pico              int,
  pedidos           int,
  obs               text not null default '',
  criado_por        uuid default auth.uid() references public.profiles(id),
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now()
);
create index if not exists lives_data_idx on public.lives (data, ini);

create table if not exists public.candidaturas (
  id             uuid primary key default gen_random_uuid(),
  live_id        uuid not null references public.lives(id) on delete cascade,
  freelancer_id  uuid not null references public.freelancers(id),
  funcao         text not null check (funcao in ('host','operador')),
  status         text not null default 'pendente' check (status in ('pendente','aceita','recusada','retirada')),
  criado_em      timestamptz not null default now(),
  decidido_em    timestamptz,
  decidido_por   uuid references public.profiles(id),
  unique (live_id, freelancer_id, funcao)
);

create table if not exists public.pagamentos_freela (
  id             uuid primary key default gen_random_uuid(),
  freelancer_id  uuid not null references public.freelancers(id),
  live_id        uuid references public.lives(id),
  descricao      text not null default '',
  valor          numeric(12,2) not null default 0,
  competencia    date not null default current_date,
  status         text not null default 'a pagar' check (status in ('a pagar','pago','cancelado')),
  nf_recebida    boolean not null default false,
  pago_em        date,
  criado_em      timestamptz not null default now(),
  unique (live_id, freelancer_id)
);

create table if not exists public.recebimentos (
  id            uuid primary key default gen_random_uuid(),
  marca_id      uuid not null references public.marcas(id),
  job_id        uuid references public.jobs(id),
  descricao     text not null default '',
  valor         numeric(12,2) not null check (valor > 0),
  vencimento    date not null,
  status        text not null default 'a receber' check (status in ('a receber','recebido','cancelado')),
  nf_emitida    boolean not null default false,
  recebido_em   date,
  criado_em     timestamptz not null default now()
);

create table if not exists public.recados (
  id         uuid primary key default gen_random_uuid(),
  de         uuid not null default auth.uid() references public.profiles(id),
  texto      text not null check (btrim(texto) <> ''),
  criado_em  timestamptz not null default now()
);

create table if not exists public.central_log (
  id     bigserial primary key,
  quem   uuid default auth.uid(),
  acao   text not null,
  em     timestamptz not null default now()
);

-- ---------- 3. Funções de apoio ----------
-- O freelancer ligado ao login atual (pelo e-mail)
create or replace function public.meu_freela_id() returns uuid
language sql stable security definer set search_path = public as $$
  select f.id from public.freelancers f join public.profiles p on lower(p.email) = lower(f.email)
  where p.id = auth.uid() and p.status = 'ativo' and f.ativo and btrim(f.email) <> '' limit 1
$$;

create or replace function public.minha_funcao() returns text
language sql stable security definer set search_path = public as $$
  select papel from public.freelancers where id = public.meu_freela_id()
$$;

create or replace function public.c_log(a text) returns void
language sql security definer set search_path = public as $$
  insert into public.central_log (quem, acao) values (auth.uid(), a)
$$;

-- Freelancer com e-mail vira convite de Seller (entra liberado no 1º login)
create or replace function public.freela_convite() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if btrim(new.email) <> '' then
    new.email := lower(btrim(new.email));
    insert into public.convites (email, nome, nivel) values (new.email, new.nome, 'seller')
      on conflict (email) do nothing;
    update public.profiles set nivel = 'seller', status = 'ativo'
      where lower(email) = new.email and status = 'pendente';
  end if;
  return new;
end $$;
drop trigger if exists freelancers_convite on public.freelancers;
create trigger freelancers_convite before insert or update of email on public.freelancers
  for each row execute function public.freela_convite();

-- Candidatura: seller só cria a própria e só pode "retirar"; gerência aceita ou recusa
create or replace function public.regras_candidatura() returns trigger
language plpgsql security definer set search_path = public as $$
declare l record; nomef text;
begin
  select * into l from public.lives where id = new.live_id;
  select nome into nomef from public.freelancers where id = new.freelancer_id;
  if tg_op = 'INSERT' then
    new.criado_em := now(); new.decidido_em := null; new.decidido_por := null;
    if not public.pode_operar() then
      if new.freelancer_id is distinct from public.meu_freela_id() then raise exception 'Você só pode se candidatar em seu nome.'; end if;
      new.status := 'pendente';
      if l.status <> 'agendada' or l.data < current_date then raise exception 'Esta live não está mais aberta.'; end if;
      if (new.funcao = 'host' and (not l.precisa_host or l.host_id is not null))
         or (new.funcao = 'operador' and (not l.precisa_operador or l.operador_id is not null)) then
        raise exception 'Esta vaga já foi preenchida.';
      end if;
    end if;
    perform public.c_log(nomef || ' se candidatou para ' || new.funcao || ' na live de ' || to_char(l.data, 'DD/MM') || ' ' || to_char(l.ini, 'HH24:MI'));
    return new;
  end if;
  -- UPDATE
  new.live_id := old.live_id; new.freelancer_id := old.freelancer_id; new.funcao := old.funcao; new.criado_em := old.criado_em;
  if not public.pode_operar() then
    if old.freelancer_id is distinct from public.meu_freela_id()
       or not ((old.status = 'pendente' and new.status = 'retirada') or (old.status = 'retirada' and new.status = 'pendente')) then
      raise exception 'Você só pode retirar ou refazer a sua candidatura enquanto a vaga está aberta.';
    end if;
    if new.status = 'pendente' and (l.status <> 'agendada' or l.data < current_date
       or (new.funcao = 'host' and l.host_id is not null) or (new.funcao = 'operador' and l.operador_id is not null)) then
      raise exception 'Esta vaga já foi preenchida.';
    end if;
    new.decidido_em := null; new.decidido_por := null;
    perform public.c_log(nomef || case when new.status = 'retirada' then ' retirou a candidatura da live de ' else ' se candidatou de novo na live de ' end || to_char(l.data, 'DD/MM'));
    return new;
  end if;
  if new.status <> old.status and new.status in ('aceita','recusada') then
    new.decidido_em := now(); new.decidido_por := auth.uid();
  end if;
  return new;
end $$;
drop trigger if exists candidaturas_regras on public.candidaturas;
create trigger candidaturas_regras before insert or update on public.candidaturas
  for each row execute function public.regras_candidatura();

-- Candidatura aceita: preenche a vaga e recusa as outras da mesma função
create or replace function public.efeito_candidatura() returns trigger
language plpgsql security definer set search_path = public as $$
declare nomef text; l record;
begin
  if new.status = 'aceita' and old.status is distinct from 'aceita' then
    select nome into nomef from public.freelancers where id = new.freelancer_id;
    select * into l from public.lives where id = new.live_id;
    if new.funcao = 'host' then update public.lives set host_id = new.freelancer_id where id = new.live_id;
    else update public.lives set operador_id = new.freelancer_id where id = new.live_id; end if;
    update public.candidaturas set status = 'recusada', decidido_em = now(), decidido_por = auth.uid()
      where live_id = new.live_id and funcao = new.funcao and id <> new.id and status = 'pendente';
    perform public.c_log('confirmou ' || nomef || ' como ' || new.funcao || ' na live de ' || to_char(l.data, 'DD/MM') || ' ' || to_char(l.ini, 'HH24:MI'));
  end if;
  return new;
end $$;
drop trigger if exists candidaturas_efeito on public.candidaturas;
create trigger candidaturas_efeito after update on public.candidaturas
  for each row execute function public.efeito_candidatura();

-- Live: histórico + pagamento automático do host e do operador quando vira "feita"
create or replace function public.horas_live(i time, f time) returns numeric
language sql immutable as $$
  select round((extract(epoch from (f - i)) / 3600.0 + case when f <= i then 24 else 0 end)::numeric, 2)
$$;

create or replace function public.log_live() returns trigger
language plpgsql security definer set search_path = public as $$
declare m text; quando text; h numeric; fr record;
begin
  if tg_op = 'DELETE' then
    select nome into m from public.marcas where id = old.marca_id;
    perform public.c_log('apagou a live ' || m || ' de ' || to_char(old.data, 'DD/MM'));
    return old;
  end if;
  select nome into m from public.marcas where id = new.marca_id;
  quando := to_char(new.data, 'DD/MM') || ' ' || to_char(new.ini, 'HH24:MI');
  if tg_op = 'INSERT' then
    perform public.c_log('criou a live ' || m || ' de ' || quando);
    return new;
  end if;
  if new.status <> old.status then
    perform public.c_log(case new.status when 'aovivo' then 'pôs no ar a live ' when 'feita' then 'encerrou a live ' when 'cancelada' then 'cancelou a live ' else 'reabriu a live ' end || m || ' de ' || quando);
  end if;
  if new.status = 'feita' and old.status <> 'feita' then
    h := public.horas_live(new.ini, new.fim);
    for fr in select * from public.freelancers where id in (new.host_id, new.operador_id) loop
      insert into public.pagamentos_freela (freelancer_id, live_id, descricao, valor, competencia)
      values (fr.id, new.id, 'Live ' || m || ' ' || quando || ' · ' || replace(h::text, '.', ',') || 'h', round(h * fr.valor_hora, 2), new.data)
      on conflict (live_id, freelancer_id) do nothing;
    end loop;
  end if;
  return new;
end $$;
drop trigger if exists lives_log on public.lives;
create trigger lives_log after insert or update or delete on public.lives
  for each row execute function public.log_live();

create or replace function public.toca_atualizado() returns trigger language plpgsql as $$
begin new.atualizado_em := now(); return new; end $$;
drop trigger if exists lives_toca on public.lives;
create trigger lives_toca before update on public.lives for each row execute function public.toca_atualizado();
drop trigger if exists jobs_toca on public.jobs;
create trigger jobs_toca before update on public.jobs for each row execute function public.toca_atualizado();

create or replace function public.log_job() returns trigger
language plpgsql security definer set search_path = public as $$
declare m text; et text[] := array['Lead','Proposta','Contrato','Briefing','Escala','No ar','Relatório','Faturado','Pago'];
begin
  select nome into m from public.marcas where id = new.marca_id;
  if tg_op = 'INSERT' then perform public.c_log('criou o job ' || m || ' · ' || new.nome);
  elsif new.etapa <> old.etapa then perform public.c_log('moveu ' || m || ' · ' || new.nome || ' para ' || et[new.etapa + 1]);
  elsif new.status <> old.status then perform public.c_log(case when new.status = 'cancelado' then 'cancelou' else 'reativou' end || ' o job ' || m || ' · ' || new.nome);
  end if;
  return new;
end $$;
drop trigger if exists jobs_log on public.jobs;
create trigger jobs_log after insert or update on public.jobs for each row execute function public.log_job();

create or replace function public.log_dinheiro() returns trigger
language plpgsql security definer set search_path = public as $$
declare n text;
begin
  if tg_table_name = 'recebimentos' then
    select nome into n from public.marcas where id = new.marca_id;
    if tg_op = 'INSERT' then perform public.c_log('lançou a receber ' || brl(new.valor) || ' de ' || n);
    elsif new.status = 'recebido' and old.status <> 'recebido' then perform public.c_log('marcou como recebido ' || brl(new.valor) || ' de ' || n); end if;
  else
    select nome into n from public.freelancers where id = new.freelancer_id;
    if tg_op = 'UPDATE' and new.status = 'pago' and old.status <> 'pago' then perform public.c_log('pagou ' || brl(new.valor) || ' a ' || n); end if;
  end if;
  return new;
end $$;
drop trigger if exists recebimentos_log on public.recebimentos;
create trigger recebimentos_log after insert or update on public.recebimentos for each row execute function public.log_dinheiro();
drop trigger if exists pagfreela_log on public.pagamentos_freela;
create trigger pagfreela_log after update on public.pagamentos_freela for each row execute function public.log_dinheiro();

-- ---------- 4. Quem vê e quem mexe ----------
alter table public.marcas            enable row level security;
alter table public.jobs              enable row level security;
alter table public.propostas         enable row level security;
alter table public.freelancers       enable row level security;
alter table public.lives             enable row level security;
alter table public.candidaturas      enable row level security;
alter table public.pagamentos_freela enable row level security;
alter table public.recebimentos      enable row level security;
alter table public.recados           enable row level security;
alter table public.central_log       enable row level security;

do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public'
    and tablename in ('marcas','jobs','propostas','freelancers','lives','candidaturas','pagamentos_freela','recebimentos','recados','central_log') loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- Marcas: todos com acesso veem (seller vê o nome da marca da live)
create policy marcas_ver    on public.marcas for select using (public.sou_ativo());
create policy marcas_criar  on public.marcas for insert with check (public.pode_operar());
create policy marcas_editar on public.marcas for update using (public.pode_operar()) with check (public.pode_operar());

-- Jobs e propostas: equipe interna vê; ADM e Gerência mexem
create policy jobs_ver      on public.jobs for select using (public.sou_interno());
create policy jobs_criar    on public.jobs for insert with check (public.pode_operar());
create policy jobs_editar   on public.jobs for update using (public.pode_operar()) with check (public.pode_operar());
create policy prop_ver      on public.propostas for select using (public.sou_interno());
create policy prop_criar    on public.propostas for insert with check (public.pode_operar());
create policy prop_editar   on public.propostas for update using (public.pode_operar()) with check (public.pode_operar());
create policy prop_apagar   on public.propostas for delete using (public.meu_nivel() = 'adm');

-- Freelancers: equipe interna vê todos; ADM e Gerência editam; cada seller vê só o próprio cadastro
create policy fre_ver       on public.freelancers for select using (public.sou_interno() or id = public.meu_freela_id());
create policy fre_criar     on public.freelancers for insert with check (public.pode_operar());
create policy fre_editar    on public.freelancers for update using (public.pode_operar()) with check (public.pode_operar());

-- Lives: equipe interna vê todas; seller vê as dele e as vagas abertas da função dele
create policy lives_ver on public.lives for select using (
  public.sou_interno()
  or host_id = public.meu_freela_id() or operador_id = public.meu_freela_id()
  or (public.meu_freela_id() is not null and status = 'agendada' and data >= current_date and (
        (public.minha_funcao() = 'host' and precisa_host and host_id is null)
     or (public.minha_funcao() = 'operador' and precisa_operador and operador_id is null))));
create policy lives_criar   on public.lives for insert with check (public.pode_operar());
create policy lives_editar  on public.lives for update using (public.pode_operar()) with check (public.pode_operar());
create policy lives_apagar  on public.lives for delete using (public.meu_nivel() = 'adm');

-- Candidaturas: seller cria/retira a própria; gerência decide
create policy cand_ver      on public.candidaturas for select using (public.sou_interno() or freelancer_id = public.meu_freela_id());
create policy cand_criar    on public.candidaturas for insert with check (public.pode_operar() or freelancer_id = public.meu_freela_id());
create policy cand_editar   on public.candidaturas for update using (public.pode_operar() or freelancer_id = public.meu_freela_id());

-- Dinheiro: só ADM; cada seller vê os próprios pagamentos
create policy pag_ver       on public.pagamentos_freela for select using (public.meu_nivel() = 'adm' or freelancer_id = public.meu_freela_id());
create policy pag_adm       on public.pagamentos_freela for all using (public.meu_nivel() = 'adm') with check (public.meu_nivel() = 'adm');
create policy rec_adm       on public.recebimentos for all using (public.meu_nivel() = 'adm') with check (public.meu_nivel() = 'adm');

-- Recados e histórico da Central: equipe interna
create policy recados_ver   on public.recados for select using (public.sou_interno());
create policy recados_criar on public.recados for insert with check (public.sou_interno() and de = auth.uid());
create policy recados_apagar on public.recados for delete using (de = auth.uid() or public.meu_nivel() = 'adm');
create policy clog_ver      on public.central_log for select using (public.sou_interno());

-- ---------- 5. Atualização ao vivo entre aparelhos ----------
do $$ declare t text; begin
  foreach t in array array['marcas','jobs','propostas','freelancers','lives','candidaturas','pagamentos_freela','recebimentos','recados'] loop
    begin execute format('alter publication supabase_realtime add table public.%I', t); exception when others then null; end;
  end loop;
end $$;
