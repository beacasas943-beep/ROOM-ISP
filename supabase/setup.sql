-- ROOM ISP · Production schema v1
-- Proyecto Supabase NUEVO. Ejecutar en SQL Editor una sola vez.
-- El navegador solo recibe permisos SELECT; todas las escrituras de negocio pasan por Edge Functions.

begin;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

DO $$ BEGIN
  create type public.access_type as enum ('PPPOE','DHCP','STATIC','HOTSPOT');
EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN
  create type public.service_status as enum ('PENDING','ACTIVE','SUSPENDED','CANCELLED');
EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN
  create type public.command_status as enum ('QUEUED','LEASED','ACK','FAILED','CANCELLED');
EXCEPTION WHEN duplicate_object THEN null; END $$;
DO $$ BEGIN
  create type public.review_status as enum ('PENDING','APPROVED','REJECTED');
EXCEPTION WHEN duplicate_object THEN null; END $$;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  status text not null default 'TRIAL' check(status in ('TRIAL','ACTIVE','PAUSED','CANCELLED')),
  owner_name text,
  support_phone text,
  timezone text not null default 'America/Lima',
  router_limit integer not null default 3 check(router_limit between 0 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'SUPERADMIN' check(role in ('SUPERADMIN','SUPPORT')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check(role in ('OWNER','ADMIN','BILLING','SUPPORT','TECHNICIAN','VIEWER')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(organization_id,user_id)
);
create index if not exists organization_members_user_idx on public.organization_members(user_id) where active;

create table if not exists public.organization_settings (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  grace_days integer not null default 0 check(grace_days between 0 and 31),
  auto_suspend boolean not null default true,
  due_day integer not null default 15 check(due_day between 1 and 28),
  customer_portal_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  code text not null,
  download_mbps integer not null check(download_mbps>0),
  upload_mbps integer not null check(upload_mbps>0),
  price numeric(12,2) not null check(price>=0),
  router_profile text not null,
  supported_access public.access_type[] not null default array['PPPOE','DHCP','STATIC']::public.access_type[],
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,code)
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  code text,
  full_name text not null,
  nickname text,
  phone text not null,
  whatsapp text,
  document_number text,
  email text,
  address text,
  district text,
  province text,
  department text,
  address_reference text,
  status text not null default 'ACTIVE' check(status in ('ACTIVE','INACTIVE','BLOCKED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,phone),
  unique(organization_id,code)
);

create table if not exists public.customer_users (
  customer_id uuid not null references public.customers(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(customer_id,user_id)
);
create index if not exists customer_users_user_idx on public.customer_users(user_id) where active;

-- MikroTik: el router siempre inicia la conexión HTTPS hacia Supabase.
create table if not exists public.routers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  identity text,
  model text,
  serial_number text,
  software_id text,
  routeros_version text,
  architecture text,
  device_key text,
  connector_version text,
  status text not null default 'PENDING' check(status in ('PENDING','ONLINE','DEGRADED','OFFLINE','REVOKED')),
  capabilities jsonb not null default '{}'::jsonb,
  health jsonb not null default '{}'::jsonb,
  last_seen_at timestamptz,
  last_inventory_at timestamptz,
  sync_interval_seconds integer not null default 120 check(sync_interval_seconds between 60 and 3600),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,name)
);
create unique index if not exists routers_device_idx on public.routers(organization_id,device_key) where device_key is not null;

create table if not exists public.router_enrollment_tokens (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  token_hash text not null unique,
  label text,
  expires_at timestamptz not null,
  claimed_at timestamptz,
  claimed_router_id uuid references public.routers(id),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.router_credentials (
  id uuid primary key default gen_random_uuid(),
  router_id uuid not null references public.routers(id) on delete cascade,
  token_hash text not null unique,
  token_prefix text not null,
  scopes jsonb not null default '["poll","inventory","result"]'::jsonb,
  last_used_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists router_credentials_active_idx on public.router_credentials(router_id) where revoked_at is null;

create table if not exists public.router_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  router_id uuid not null references public.routers(id) on delete cascade,
  name text not null,
  rate_limit text,
  local_address text,
  remote_address text,
  only_one text,
  fingerprint text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(router_id,name)
);

create table if not exists public.router_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  router_id uuid not null references public.routers(id) on delete cascade,
  source_type public.access_type not null,
  source_key text not null,
  display_name text,
  comment text,
  mac_address text,
  ip_address inet,
  router_profile text,
  metadata jsonb not null default '{}'::jsonb,
  fingerprint text not null,
  state text not null default 'UNMATCHED' check(state in ('UNMATCHED','MATCHED','IGNORED','STALE')),
  customer_id uuid references public.customers(id),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  unique(router_id,source_type,source_key)
);

create table if not exists public.router_inventory_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  router_id uuid not null references public.routers(id) on delete cascade,
  item_type text not null,
  item_key text not null,
  data jsonb not null default '{}'::jsonb,
  fingerprint text not null,
  last_seen_at timestamptz not null default now(),
  unique(router_id,item_type,item_key)
);

create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  plan_id uuid references public.plans(id),
  router_id uuid references public.routers(id),
  access_type public.access_type not null,
  status public.service_status not null default 'PENDING',
  pppoe_username text,
  dhcp_mac text,
  static_ip inet,
  hotspot_username text,
  router_source_key text,
  paid_until date,
  installed_at date,
  suspended_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check((access_type<>'PPPOE') or pppoe_username is not null),
  check((access_type<>'DHCP') or dhcp_mac is not null),
  check((access_type<>'STATIC') or static_ip is not null),
  check((access_type<>'HOTSPOT') or hotspot_username is not null)
);
create unique index if not exists services_pppoe_unique on public.services(router_id,pppoe_username) where pppoe_username is not null and status<>'CANCELLED';
create index if not exists services_org_status_idx on public.services(organization_id,status);

create table if not exists public.service_credentials (
  service_id uuid primary key references public.services(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  username text,
  secret_ciphertext text,
  secret_iv text,
  updated_at timestamptz not null default now()
);

create table if not exists public.network_commands (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  router_id uuid not null references public.routers(id) on delete cascade,
  service_id uuid references public.services(id),
  customer_id uuid references public.customers(id),
  command_type text not null check(command_type in ('ENABLE','SUSPEND','PLAN_CHANGE','CREATE_ACCESS','REMOVE_ACCESS','INVENTORY_NOW','TERMINAL_READ','ROUTER_CONFIG')),
  payload jsonb not null default '{}'::jsonb,
  idempotency_key text not null unique,
  status public.command_status not null default 'QUEUED',
  available_at timestamptz not null default now(),
  lease_until timestamptz,
  attempts integer not null default 0,
  max_attempts integer not null default 5,
  ack_payload jsonb,
  acked_at timestamptz,
  last_error text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists network_commands_poll_idx on public.network_commands(router_id,status,available_at) where status in ('QUEUED','LEASED');

-- Cobranza.
create table if not exists public.payment_channels (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  type text not null check(type in ('YAPE','PLIN','BANK_TRANSFER','CASH','PAYMENT_LINK')),
  display_name text not null,
  receiver_name text not null,
  account_reference text,
  instructions text,
  qr_object_path text,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  due_date date not null,
  subtotal numeric(12,2) not null,
  total numeric(12,2) not null,
  balance numeric(12,2) not null,
  status text not null default 'PENDING' check(status in ('PENDING','PARTIAL','PAID','VOID','OVERDUE')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(service_id,period_start)
);
create index if not exists invoices_collection_idx on public.invoices(organization_id,status,due_date);

create table if not exists public.payment_reports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  service_id uuid references public.services(id),
  invoice_id uuid not null references public.invoices(id),
  channel_id uuid references public.payment_channels(id),
  amount numeric(12,2) not null check(amount>0),
  operation_reference text,
  proof_object_path text,
  status public.review_status not null default 'PENDING',
  source text not null default 'WEB',
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  service_id uuid references public.services(id),
  invoice_id uuid references public.invoices(id),
  report_id uuid unique references public.payment_reports(id),
  amount numeric(12,2) not null check(amount>0),
  method text not null,
  external_reference text,
  paid_at timestamptz not null default now()
);

-- Soporte.
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid references public.customers(id),
  service_id uuid references public.services(id),
  subject text not null,
  detail text,
  priority text not null default 'NORMAL' check(priority in ('LOW','NORMAL','HIGH','CRITICAL')),
  status text not null default 'OPEN' check(status in ('OPEN','IN_PROGRESS','RESOLVED','CLOSED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.support_messages (
  id bigint generated always as identity primary key,
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sender_user_id uuid references auth.users(id),
  sender_type text not null check(sender_type in ('CUSTOMER','STAFF','SYSTEM')),
  body text not null,
  created_at timestamptz not null default now()
);

-- Solicitudes del portal cliente.
create table if not exists public.customer_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  service_id uuid references public.services(id) on delete cascade,
  request_type text not null check(request_type in ('PLAN_CHANGE','CANCEL_SERVICE','OTHER')),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'PENDING' check(status in ('PENDING','APPROVED','REJECTED','COMPLETED')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id)
);

-- GIS FTTH.
create table if not exists public.network_nodes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  node_type text not null check(node_type in ('POP','OLT','NAP','SPLITTER','OTHER')),
  name text not null,
  code text,
  status text not null default 'ACTIVE' check(status in ('ACTIVE','DEGRADED','DOWN','MAINTENANCE','DISABLED','PLANNED')),
  latitude numeric(10,7) not null check(latitude between -90 and 90),
  longitude numeric(10,7) not null check(longitude between -180 and 180),
  address text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,code)
);

create table if not exists public.network_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text,
  from_node_id uuid references public.network_nodes(id) on delete set null,
  to_node_id uuid references public.network_nodes(id) on delete set null,
  link_type text not null default 'FIBER' check(link_type in ('FIBER','UPLINK','DROP')),
  fiber_count integer not null default 1 check(fiber_count between 1 and 288),
  length_m numeric(12,2),
  status text not null default 'ACTIVE' check(status in ('ACTIVE','FAULT','PLANNED','DISABLED')),
  geometry jsonb not null default '[]'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.service_locations (
  service_id uuid primary key references public.services(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  parent_node_id uuid references public.network_nodes(id) on delete set null,
  label text not null default 'Casa',
  address text,
  latitude numeric(10,7) check(latitude between -90 and 90),
  longitude numeric(10,7) check(longitude between -180 and 180),
  source text not null default 'STAFF',
  updated_at timestamptz not null default now()
);

-- Credenciales de integraciones externas siempre cifradas por Edge Functions.
create table if not exists public.integration_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null check(provider in ('SMARTOLT')),
  public_config jsonb not null default '{}'::jsonb,
  secret_ciphertext text,
  secret_iv text,
  status text not null default 'CONFIGURED' check(status in ('CONFIGURED','ACTIVE','ERROR','DISABLED')),
  last_sync_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,provider)
);

create table if not exists public.olt_devices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_id text not null,
  name text not null,
  vendor text,
  model text,
  provider_code text,
  status text not null default 'UNKNOWN' check(status in ('ONLINE','DEGRADED','OFFLINE','UNKNOWN')),
  last_seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,provider_id)
);

create table if not exists public.olt_pons (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  olt_id uuid not null references public.olt_devices(id) on delete cascade,
  frame integer,
  slot integer,
  port integer not null,
  label text,
  status text not null default 'UNKNOWN',
  onu_count integer not null default 0,
  online_onu_count integer not null default 0,
  average_signal numeric(8,2),
  tx_power numeric(8,2),
  last_seen_at timestamptz,
  unique(olt_id,frame,slot,port)
);

create table if not exists public.olt_onus (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_external_id text,
  olt_id uuid references public.olt_devices(id) on delete cascade,
  pon_id uuid references public.olt_pons(id) on delete set null,
  service_id uuid references public.services(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  name text,
  serial_number text not null,
  onu_id text,
  olt_name text,
  pon_label text,
  status text not null default 'UNKNOWN' check(status in ('ONLINE','LOS','DYING_GASP','OFFLINE','UNKNOWN')),
  rx_dbm numeric(7,2),
  tx_dbm numeric(7,2),
  distance_m integer,
  last_seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  unique(organization_id,serial_number)
);

-- Hotspot.
create table if not exists public.hotspot_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  router_id uuid not null references public.routers(id),
  name text not null,
  quantity integer not null check(quantity between 1 and 100),
  profile_name text not null,
  duration_minutes integer,
  price numeric(12,2),
  status text not null default 'QUEUED' check(status in ('QUEUED','READY','CANCELLED')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.hotspot_vouchers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  batch_id uuid not null references public.hotspot_batches(id) on delete cascade,
  username text not null,
  secret_hash text not null,
  secret_ciphertext text,
  secret_iv text,
  status text not null default 'AVAILABLE' check(status in ('AVAILABLE','SOLD','ACTIVE','EXPIRED','REVOKED')),
  sold_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  unique(batch_id,username)
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid references public.organizations(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_type text not null default 'USER',
  action text not null,
  entity_type text not null,
  entity_id text,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.domain_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  action text not null,
  patch jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Seguridad.
create or replace function private.is_platform_admin() returns boolean language sql stable security definer set search_path=public,auth as $$
  select auth.uid() is not null and exists(select 1 from public.platform_admins where user_id=auth.uid() and active)
$$;
create or replace function private.is_org_member(p_org uuid) returns boolean language sql stable security definer set search_path=public,auth as $$
  select auth.uid() is not null and (private.is_platform_admin() or exists(
    select 1 from public.organization_members m join public.organizations o on o.id=m.organization_id
    where m.organization_id=p_org and m.user_id=auth.uid() and m.active and o.status in ('TRIAL','ACTIVE')
  ))
$$;
create or replace function private.has_org_role(p_org uuid,p_roles text[]) returns boolean language sql stable security definer set search_path=public,auth as $$
  select private.is_platform_admin() or exists(
    select 1 from public.organization_members m join public.organizations o on o.id=m.organization_id
    where m.organization_id=p_org and m.user_id=auth.uid() and m.active and m.role=any(p_roles) and o.status in ('TRIAL','ACTIVE')
  )
$$;
create or replace function private.is_customer(p_customer uuid) returns boolean language sql stable security definer set search_path=public,auth as $$
  select auth.uid() is not null and exists(
    select 1 from public.customer_users cu join public.customers c on c.id=cu.customer_id join public.organizations o on o.id=c.organization_id
    left join public.organization_settings os on os.organization_id=o.id
    where cu.customer_id=p_customer and cu.user_id=auth.uid() and cu.active and c.status='ACTIVE' and o.status in ('TRIAL','ACTIVE') and coalesce(os.customer_portal_enabled,true)
  )
$$;
create or replace function private.is_customer_org(p_org uuid) returns boolean language sql stable security definer set search_path=public,auth as $$
  select auth.uid() is not null and exists(
    select 1 from public.customer_users cu join public.customers c on c.id=cu.customer_id join public.organizations o on o.id=c.organization_id
    left join public.organization_settings os on os.organization_id=o.id
    where cu.user_id=auth.uid() and cu.active and c.status='ACTIVE' and c.organization_id=p_org and o.status in ('TRIAL','ACTIVE') and coalesce(os.customer_portal_enabled,true)
  )
$$;
grant usage on schema private to authenticated;
grant execute on function private.is_platform_admin(),private.is_org_member(uuid),private.has_org_role(uuid,text[]),private.is_customer(uuid),private.is_customer_org(uuid) to authenticated;

create or replace function private.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;
DO $$ declare t text; begin foreach t in array array['organizations','organization_settings','plans','customers','routers','services','payment_channels','invoices','support_tickets','network_nodes','integration_connections','olt_devices'] loop
  execute format('drop trigger if exists %I_touch on public.%I',t,t);
  execute format('create trigger %I_touch before update on public.%I for each row execute function private.touch_updated_at()',t,t);
end loop; end $$;

create or replace function private.bootstrap_org_defaults() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.organization_settings(organization_id) values(new.id) on conflict do nothing; return new; end $$;
drop trigger if exists organizations_defaults on public.organizations;
create trigger organizations_defaults after insert on public.organizations for each row execute function private.bootstrap_org_defaults();

-- Router enrollment: token temporal -> credencial agente hasheada.
create or replace function public.claim_router_enrollment(p_enrollment_hash text,p_agent_hash text,p_token_prefix text,p_device jsonb,p_capabilities jsonb)
returns table(router_id uuid,organization_id uuid,poll_seconds integer) language plpgsql security definer set search_path=public as $$
declare e public.router_enrollment_tokens%rowtype; rid uuid; ident text:=left(coalesce(p_device->>'identity','MikroTik'),120); dkey text:=nullif(left(coalesce(p_device->>'software_id',''),120),'');
begin
  select * into e from public.router_enrollment_tokens where token_hash=p_enrollment_hash and claimed_at is null and expires_at>now() for update;
  if not found then raise exception 'ENROLLMENT_INVALID_OR_EXPIRED'; end if;
  select id into rid from public.routers where organization_id=e.organization_id and ((dkey is not null and device_key=dkey) or name=ident) limit 1 for update;
  if rid is null then
    insert into public.routers(organization_id,name,identity,model,serial_number,software_id,routeros_version,architecture,device_key,connector_version,status,capabilities,last_seen_at)
    values(e.organization_id,ident,ident,left(p_device->>'model',120),left(p_device->>'serial_number',120),left(p_device->>'software_id',120),left(p_device->>'routeros_version',80),left(p_device->>'architecture',80),dkey,left(p_device->>'connector_version',80),'ONLINE',coalesce(p_capabilities,'{}'),now()) returning id into rid;
  else
    update public.routers set identity=ident,model=left(p_device->>'model',120),serial_number=coalesce(nullif(left(p_device->>'serial_number',120),''),serial_number),software_id=coalesce(nullif(left(p_device->>'software_id',120),''),software_id),routeros_version=left(p_device->>'routeros_version',80),architecture=left(p_device->>'architecture',80),device_key=coalesce(dkey,device_key),connector_version=left(p_device->>'connector_version',80),status='ONLINE',capabilities=coalesce(p_capabilities,'{}'),last_seen_at=now() where id=rid;
  end if;
  update public.router_credentials set revoked_at=now() where router_id=rid and revoked_at is null;
  insert into public.router_credentials(router_id,token_hash,token_prefix,expires_at) values(rid,p_agent_hash,p_token_prefix,now()+interval '180 days');
  update public.router_enrollment_tokens set claimed_at=now(),claimed_router_id=rid where id=e.id;
  return query select rid,e.organization_id,120;
end $$;

create or replace function public.lease_router_command(p_router_id uuid) returns setof public.network_commands language plpgsql security definer set search_path=public as $$
declare cid uuid;
begin
  select id into cid from public.network_commands where router_id=p_router_id and status='QUEUED' and available_at<=now() and attempts<max_attempts order by available_at,created_at for update skip locked limit 1;
  if cid is null then return; end if;
  return query update public.network_commands set status='LEASED',lease_until=now()+interval '3 minutes',attempts=attempts+1 where id=cid returning *;
end $$;

create or replace function public.release_expired_command_leases() returns integer language plpgsql security definer set search_path=public as $$
declare n integer; begin update public.network_commands set status=case when attempts>=max_attempts then 'FAILED'::public.command_status else 'QUEUED'::public.command_status end,lease_until=null,available_at=now()+interval '1 minute' where status='LEASED' and lease_until<now();get diagnostics n=row_count;return n;end $$;

create or replace function public.generate_due_invoices(p_org uuid default null) returns integer language plpgsql security definer set search_path=public as $$
declare n integer;
begin
  insert into public.invoices(organization_id,customer_id,service_id,period_start,period_end,due_date,subtotal,total,balance,status)
  select s.organization_id,s.customer_id,s.id,date_trunc('month',current_date)::date,(date_trunc('month',current_date)+interval '1 month - 1 day')::date,
         (date_trunc('month',current_date)+(coalesce(os.due_day,15)-1)*interval '1 day')::date,p.price,p.price,p.price,'PENDING'
  from public.services s join public.plans p on p.id=s.plan_id left join public.organization_settings os on os.organization_id=s.organization_id
  where s.status in ('ACTIVE','SUSPENDED') and s.plan_id is not null and (p_org is null or s.organization_id=p_org)
  on conflict(service_id,period_start) do nothing;
  get diagnostics n=row_count; return n;
end $$;

create or replace function public.review_customer_payment_report(p_report_id uuid,p_reviewer uuid,p_approve boolean,p_note text default null)
returns table(report_id uuid,final_status public.review_status,payment_id uuid,command_id uuid) language plpgsql security definer set search_path=public as $$
declare r public.payment_reports%rowtype;i public.invoices%rowtype;s public.services%rowtype;pid uuid;cid uuid;new_balance numeric;
begin
  select * into r from public.payment_reports where id=p_report_id for update;if not found then raise exception 'PAYMENT_REPORT_NOT_FOUND';end if;
  if r.status<>'PENDING' then raise exception 'PAYMENT_REPORT_ALREADY_REVIEWED';end if;
  if not p_approve then update public.payment_reports set status='REJECTED',reviewed_by=p_reviewer,reviewed_at=now(),rejection_reason=nullif(left(coalesce(p_note,''),240),'') where id=r.id;return query select r.id,'REJECTED'::public.review_status,null::uuid,null::uuid;return;end if;
  select * into i from public.invoices where id=r.invoice_id for update;if not found or i.status in ('PAID','VOID') then raise exception 'INVOICE_NOT_PAYABLE';end if;
  insert into public.payments(organization_id,customer_id,service_id,invoice_id,report_id,amount,method,external_reference) values(r.organization_id,r.customer_id,i.service_id,i.id,r.id,r.amount,'REPORTED',r.operation_reference) returning id into pid;
  new_balance:=greatest(0,i.balance-r.amount);
  update public.invoices set balance=new_balance,status=case when new_balance<=0 then 'PAID' when new_balance<total then 'PARTIAL' else status end where id=i.id;
  update public.payment_reports set status='APPROVED',reviewed_by=p_reviewer,reviewed_at=now(),rejection_reason=null where id=r.id;
  select * into s from public.services where id=i.service_id for update;
  if found and new_balance<=0 then
    update public.services set paid_until=greatest(coalesce(paid_until,i.period_end),i.period_end) where id=s.id;
    if s.status='SUSPENDED' and s.router_id is not null then
      insert into public.network_commands(organization_id,router_id,service_id,customer_id,command_type,payload,idempotency_key,created_by)
      values(r.organization_id,s.router_id,s.id,r.customer_id,'ENABLE',jsonb_build_object('access_type',s.access_type,'source_key',coalesce(s.router_source_key,s.pppoe_username,s.dhcp_mac,s.static_ip::text,s.hotspot_username)),'payment-enable:'||r.id::text,p_reviewer)
      on conflict(idempotency_key) do update set idempotency_key=excluded.idempotency_key returning id into cid;
    end if;
  end if;
  return query select r.id,'APPROVED'::public.review_status,pid,cid;
end $$;

create or replace function public.run_room_maintenance() returns jsonb language plpgsql security definer set search_path=public as $$
declare leases integer;overdue integer;cuts integer;offline integer; generated integer;
begin
  leases:=public.release_expired_command_leases();
  generated:=public.generate_due_invoices(null);
  update public.invoices set status='OVERDUE' where status in ('PENDING','PARTIAL') and balance>0 and due_date<current_date; get diagnostics overdue=row_count;
  insert into public.network_commands(organization_id,router_id,service_id,customer_id,command_type,payload,idempotency_key)
  select s.organization_id,s.router_id,s.id,s.customer_id,'SUSPEND',jsonb_build_object('access_type',s.access_type,'source_key',coalesce(s.router_source_key,s.pppoe_username,s.dhcp_mac,s.static_ip::text,s.hotspot_username),'reason','PAYMENT_OVERDUE','invoice_id',i.id),'auto-suspend:'||i.id::text
  from public.services s join public.invoices i on i.service_id=s.id and i.balance>0 and i.status in ('OVERDUE','PARTIAL','PENDING') left join public.organization_settings os on os.organization_id=s.organization_id
  where s.status='ACTIVE' and s.router_id is not null and coalesce(os.auto_suspend,true) and i.due_date+coalesce(os.grace_days,0)<current_date
  on conflict(idempotency_key) do nothing; get diagnostics cuts=row_count;
  update public.routers set status='OFFLINE' where status in ('ONLINE','DEGRADED') and last_seen_at<now()-make_interval(secs=>greatest(sync_interval_seconds*3,900)); get diagnostics offline=row_count;
  delete from public.domain_events where created_at<now()-interval '7 days';
  delete from public.router_enrollment_tokens where claimed_at is null and expires_at<now()-interval '1 day';
  delete from public.network_commands where status in ('ACK','FAILED','CANCELLED') and created_at<now()-interval '30 days';
  return jsonb_build_object('leases_released',leases,'invoices_generated',generated,'invoices_overdue',overdue,'suspensions_queued',cuts,'routers_offline',offline);
end $$;

revoke all on function public.claim_router_enrollment(text,text,text,jsonb,jsonb),public.lease_router_command(uuid),public.release_expired_command_leases(),public.generate_due_invoices(uuid),public.review_customer_payment_report(uuid,uuid,boolean,text),public.run_room_maintenance() from public,anon,authenticated;
grant execute on function public.claim_router_enrollment(text,text,text,jsonb,jsonb),public.lease_router_command(uuid),public.release_expired_command_leases(),public.generate_due_invoices(uuid),public.review_customer_payment_report(uuid,uuid,boolean,text),public.run_room_maintenance() to service_role;

-- RLS: lectura limitada por rol; ninguna escritura directa de negocio desde el navegador.
DO $$ declare t text; begin foreach t in array array['organizations','platform_admins','organization_members','organization_settings','plans','customers','customer_users','routers','router_enrollment_tokens','router_credentials','router_profiles','router_observations','router_inventory_items','services','service_credentials','network_commands','payment_channels','invoices','payment_reports','payments','support_tickets','support_messages','customer_requests','network_nodes','network_links','service_locations','integration_connections','olt_devices','olt_pons','olt_onus','hotspot_batches','hotspot_vouchers','audit_logs','domain_events'] loop execute format('alter table public.%I enable row level security',t); end loop; end $$;

-- Sólo SELECT al rol authenticated en las tablas visibles. service_role conserva acceso administrativo.
grant select on public.organizations,public.platform_admins,public.organization_members,public.organization_settings,public.plans,public.customers,public.customer_users,public.routers,public.router_profiles,public.router_observations,public.router_inventory_items,public.services,public.network_commands,public.payment_channels,public.invoices,public.payment_reports,public.payments,public.support_tickets,public.support_messages,public.customer_requests,public.network_nodes,public.network_links,public.service_locations,public.olt_devices,public.olt_pons,public.olt_onus,public.hotspot_batches,public.hotspot_vouchers,public.audit_logs,public.domain_events to authenticated;
revoke insert,update,delete,truncate,references,trigger on all tables in schema public from anon,authenticated;

create policy organizations_read on public.organizations for select to authenticated using(private.is_platform_admin() or private.is_org_member(id));
create policy platform_admin_self_read on public.platform_admins for select to authenticated using(user_id=auth.uid() or private.is_platform_admin());
create policy organization_members_read on public.organization_members for select to authenticated using(private.is_org_member(organization_id));
create policy organization_settings_read on public.organization_settings for select to authenticated using(private.is_org_member(organization_id));
create policy customer_users_self_read on public.customer_users for select to authenticated using(user_id=auth.uid() or private.is_platform_admin());

DO $$ declare t text; begin foreach t in array array['customers','routers','router_profiles','router_observations','router_inventory_items','services','network_commands','payment_channels','invoices','payment_reports','payments','support_tickets','support_messages','customer_requests','network_nodes','network_links','service_locations','olt_devices','olt_pons','olt_onus','hotspot_batches','hotspot_vouchers','domain_events'] loop
  execute format('create policy %I_org_read on public.%I for select to authenticated using(private.is_org_member(organization_id))',t,t);
end loop; end $$;
create policy audit_logs_platform_read on public.audit_logs for select to authenticated using(private.is_platform_admin() or (organization_id is not null and private.has_org_role(organization_id,array['OWNER','ADMIN']::text[])));
create policy plans_org_read on public.plans for select to authenticated using(private.is_org_member(organization_id));
create policy plans_customer_read on public.plans for select to authenticated using(active and private.is_customer_org(organization_id));

-- Cliente final: solamente sus propios datos.
create policy customers_self on public.customers for select to authenticated using(private.is_customer(id));
create policy services_self on public.services for select to authenticated using(private.is_customer(customer_id));
create policy invoices_self on public.invoices for select to authenticated using(private.is_customer(customer_id));
create policy payments_self on public.payments for select to authenticated using(private.is_customer(customer_id));
create policy reports_self on public.payment_reports for select to authenticated using(private.is_customer(customer_id));
create policy tickets_self on public.support_tickets for select to authenticated using(customer_id is not null and private.is_customer(customer_id));
create policy ticket_messages_self on public.support_messages for select to authenticated using(exists(select 1 from public.support_tickets t where t.id=support_messages.ticket_id and t.customer_id is not null and private.is_customer(t.customer_id)));
create policy locations_self on public.service_locations for select to authenticated using(private.is_customer(customer_id));
create policy channels_customer on public.payment_channels for select to authenticated using(active and private.is_customer_org(organization_id));
create policy requests_self on public.customer_requests for select to authenticated using(private.is_customer(customer_id));

commit;
-- ROOM ISP · Storage privado
begin;
create or replace function private.safe_uuid(p text) returns uuid language plpgsql immutable as $$ begin return p::uuid; exception when others then return null; end $$;
grant execute on function private.safe_uuid(text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values
 ('payment-proofs','payment-proofs',false,2097152,array['image/jpeg','image/png','image/webp']),
 ('payment-assets','payment-assets',false,2097152,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

alter table storage.objects enable row level security;

drop policy if exists room_payment_assets_select on storage.objects;
create policy room_payment_assets_select on storage.objects for select to authenticated using(
  bucket_id='payment-assets' and (
    private.is_org_member(private.safe_uuid((storage.foldername(name))[1])) or
    private.is_customer_org(private.safe_uuid((storage.foldername(name))[1]))
  )
);
drop policy if exists room_payment_assets_insert on storage.objects;
create policy room_payment_assets_insert on storage.objects for insert to authenticated with check(
  bucket_id='payment-assets' and private.has_org_role(private.safe_uuid((storage.foldername(name))[1]),array['OWNER','ADMIN','BILLING']::text[])
);
drop policy if exists room_payment_assets_update on storage.objects;
create policy room_payment_assets_update on storage.objects for update to authenticated using(
  bucket_id='payment-assets' and private.has_org_role(private.safe_uuid((storage.foldername(name))[1]),array['OWNER','ADMIN','BILLING']::text[])
) with check(
  bucket_id='payment-assets' and private.has_org_role(private.safe_uuid((storage.foldername(name))[1]),array['OWNER','ADMIN','BILLING']::text[])
);
drop policy if exists room_payment_assets_delete on storage.objects;
create policy room_payment_assets_delete on storage.objects for delete to authenticated using(
  bucket_id='payment-assets' and private.has_org_role(private.safe_uuid((storage.foldername(name))[1]),array['OWNER','ADMIN']::text[])
);

drop policy if exists room_payment_proofs_select on storage.objects;
create policy room_payment_proofs_select on storage.objects for select to authenticated using(
  bucket_id='payment-proofs' and (
    private.is_customer(private.safe_uuid((storage.foldername(name))[1])) or
    exists(select 1 from public.customers c where c.id=private.safe_uuid((storage.foldername(name))[1]) and private.is_org_member(c.organization_id))
  )
);
drop policy if exists room_payment_proofs_insert on storage.objects;
create policy room_payment_proofs_insert on storage.objects for insert to authenticated with check(
  bucket_id='payment-proofs' and private.is_customer(private.safe_uuid((storage.foldername(name))[1]))
);
commit;
-- ROOM ISP · mantenimiento SQL sin Edge Function por ciclo.
create extension if not exists pg_cron with schema pg_catalog;
do $$ declare j record; begin for j in select jobid from cron.job where jobname='room-maintenance' loop perform cron.unschedule(j.jobid); end loop; end $$;
select cron.schedule('room-maintenance','*/15 * * * *',$$select public.run_room_maintenance();$$);
