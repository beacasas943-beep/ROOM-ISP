// ROOM ISP v5.0-RC4.3 · Data layer · cliente celular/DNI + PIN
(() => {
  "use strict";
  const cfg = window.ROOM_ISP_CONFIG || {};
  const portal = document.body?.dataset?.portal || "public";
  const storageKey = `room-isp-auth-${portal}-v1`;
  const validUrl = /^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(String(cfg.SUPABASE_URL || ""));
  const configured = validUrl && String(cfg.SUPABASE_PUBLISHABLE_KEY || "").length > 20 && window.supabase?.createClient;
  let client = null;
  let session = null;
  let identity = null;

  const normalizePhone = (value) => {
    let digits = String(value || "").replace(/\D/g, "");
    if (digits.startsWith("51") && digits.length === 11) return `+${digits}`;
    if (digits.length === 9) return `${cfg.DEFAULT_COUNTRY_CODE || "+51"}${digits}`;
    if (String(value || "").trim().startsWith("+") && digits.length >= 10) return `+${digits}`;
    throw new Error("PHONE_INVALID");
  };

  async function init() {
    if (!configured) return { configured: false, portal, session: null };
    client = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_PUBLISHABLE_KEY, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        storageKey,
      },
      realtime: { params: { eventsPerSecond: 2 } },
    });
    session = (await client.auth.getSession()).data.session || null;
    client.auth.onAuthStateChange((_event, next) => { session = next; });
    if (session) {
      try { identity = await whoami(); }
      catch { await client.auth.signOut({ scope: "local" }); session = null; identity = null; }
    }
    return { configured: true, portal, session, identity };
  }

  async function invoke(functionName, body, { auth = true } = {}) {
    if (!configured || !client) throw new Error("SUPABASE_NOT_CONFIGURED");
    if (auth && !session?.access_token) throw new Error("AUTH_REQUIRED");
    const headers = { "Content-Type": "application/json", apikey: cfg.SUPABASE_PUBLISHABLE_KEY };
    if (auth) headers.Authorization = `Bearer ${session.access_token}`;
    const response = await fetch(`${cfg.SUPABASE_URL}/functions/v1/${functionName}`, {
      method: "POST", headers, body: JSON.stringify(body || {}), cache: "no-store"
    });
    const text = await response.text();
    let data = null;
    try { data = JSON.parse(text); } catch { data = { ok: false, error: text || `HTTP_${response.status}` }; }
    if (!response.ok || data?.ok === false) throw new Error(data?.error || `HTTP_${response.status}`);
    return data;
  }

  async function api(action, payload = {}) {
    return invoke(cfg.ROOM_API_FUNCTION || "room-api", { action, ...payload, request_id: crypto.randomUUID() });
  }

  async function whoami() {
    if (!session) return null;
    const data = await api("whoami");
    const allowed = Array.isArray(data.portals) ? data.portals : [];
    const required = portal === "customer" ? "customer" : portal;
    if (!allowed.includes(required)) throw new Error("PORTAL_ACCESS_DENIED");
    identity = data;
    return data;
  }

  async function signInStaff(identityValue, password) {
    if (!configured || !client) throw new Error("SUPABASE_NOT_CONFIGURED");
    const value = String(identityValue || "").trim();
    if (!value || !password) throw new Error("CREDENTIALS_REQUIRED");
    const credentials = value.includes("@")
      ? { email: value.toLowerCase(), password }
      : { phone: normalizePhone(value), password };
    const { data, error } = await client.auth.signInWithPassword(credentials);
    if (error) throw error;
    session = data.session;
    try { identity = await whoami(); }
    catch (error) { await client.auth.signOut({ scope: "local" }); session = null; throw error; }
    return { session, identity };
  }

  async function signInCustomer(identifier, pin) {
    if (!configured || !client) throw new Error("SUPABASE_NOT_CONFIGURED");
    const identityValue = String(identifier || "").trim();
    const pinValue = String(pin || "").trim();
    if (!identityValue || !/^\d{8}$/.test(pinValue)) throw new Error("CUSTOMER_LOGIN_INVALID");
    const orgSlug = new URLSearchParams(location.search).get("org") || "";
    const data = await invoke(cfg.CUSTOMER_AUTH_FUNCTION || "customer-auth", { identifier: identityValue, pin: pinValue, organization_slug: orgSlug }, { auth: false });
    const { data: setData, error } = await client.auth.setSession({ access_token: data.access_token, refresh_token: data.refresh_token });
    if (error || !setData.session) throw error || new Error("INVALID_LOGIN_CREDENTIALS");
    session = setData.session;
    try { identity = await whoami(); }
    catch (error) { await client.auth.signOut({ scope: "local" }); session = null; throw error; }
    return { session, identity };
  }

  async function changeCustomerPin(pin) {
    if (!client || !session) throw new Error("AUTH_REQUIRED");
    const value = String(pin || "").trim();
    if (!/^\d{8}$/.test(value)) throw new Error("CUSTOMER_PIN_INVALID");
    const { error } = await client.auth.updateUser({ password: value, data: { must_change_password: false } });
    if (error) throw error;
    identity = await whoami();
    return true;
  }

  async function requestCustomerOtp(phone, channel = "sms") {
    if (!configured || !client) throw new Error("SUPABASE_NOT_CONFIGURED");
    const normalized = normalizePhone(phone);
    const { error } = await client.auth.signInWithOtp({
      phone: normalized,
      options: { shouldCreateUser: false, channel: channel === "whatsapp" ? "whatsapp" : "sms" }
    });
    if (error) throw error;
    return normalized;
  }

  async function verifyCustomerOtp(phone, token) {
    const normalized = normalizePhone(phone);
    const { data, error } = await client.auth.verifyOtp({ phone: normalized, token: String(token || "").trim(), type: "sms" });
    if (error) throw error;
    session = data.session;
    try { identity = await whoami(); }
    catch (error) { await client.auth.signOut({ scope: "local" }); session = null; throw error; }
    return { session, identity };
  }

  async function signOut() {
    if (client) await client.auth.signOut({ scope: "local" });
    session = null; identity = null;
  }

  async function changePassword(password) {
    if (!client || !session) throw new Error("AUTH_REQUIRED");
    if (String(password || "").length < 10) throw new Error("PASSWORD_TOO_SHORT");
    const { error } = await client.auth.updateUser({ password, data: { must_change_password: false } });
    if (error) throw error;
    identity = await whoami();
    return true;
  }

  function table(name) {
    if (!client) throw new Error("SUPABASE_NOT_CONFIGURED");
    return client.from(name);
  }

  async function upload(bucket, path, file, options = {}) {
    if (!client || !session) throw new Error("AUTH_REQUIRED");
    const { data, error } = await client.storage.from(bucket).upload(path, file, { upsert: !!options.upsert, contentType: file.type || options.contentType });
    if (error) throw error;
    return data;
  }

  async function signedUrl(bucket, path, expires = 900) {
    if (!client || !path) return null;
    const { data, error } = await client.storage.from(bucket).createSignedUrl(path, expires);
    if (error) return null;
    return data.signedUrl;
  }

  async function mikrotikInstaller(organizationId, label) {
    return invoke(cfg.MIKROTIK_INSTALLER_FUNCTION || "mikrotik-installer", { action: "issue", organization_id: organizationId, label });
  }

  async function mikrotikInstallerStatus(organizationId, enrollmentId) {
    return invoke(cfg.MIKROTIK_INSTALLER_FUNCTION || "mikrotik-installer", { action: "status", organization_id: organizationId, enrollment_id: enrollmentId });
  }

  async function smartoltSync(organizationId, mode = "full") {
    return invoke(cfg.SMARTOLT_FUNCTION || "smartolt-sync", { organization_id: organizationId, mode });
  }

  async function identityLookup(organizationId, documentNumber) {
    return invoke(cfg.IDENTITY_LOOKUP_FUNCTION || "identity-lookup", { organization_id: organizationId, document_number: String(documentNumber || "").trim() });
  }

  window.RoomData = Object.freeze({
    init, api, invoke, whoami, signInStaff, signInCustomer, changeCustomerPin, requestCustomerOtp, verifyCustomerOtp, signOut, changePassword,
    table, upload, signedUrl, mikrotikInstaller, mikrotikInstallerStatus, smartoltSync, identityLookup, normalizePhone,
    get client(){ return client; }, get session(){ return session; }, get identity(){ return identity; },
    configured, portal, config: cfg
  });
})();

