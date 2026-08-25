// ============================================================================
// Atendify — Phase 1 backend adapter (Supabase)
// ============================================================================
// Drop-in replacement for the window.storage shim currently defined in
// atendify.html (search for `NS = 'atendify_storage:'`). Same four methods,
// same argument shapes, same promise-of-object return shapes — so every
// existing call site (window.storage.get/set/delete/list, ~1,000+ places)
// keeps working unmodified. What changes is where the data actually lives:
// a shared Postgres table on Supabase instead of one browser's localStorage.
//
// HOW TO WIRE THIS IN (do this once real Supabase credentials exist):
//   1. Add, right after the existing <script src="https://unpkg.com/@supabase/supabase-js@2"></script>
//      (or the matching CDN tag for whatever supabase-js version is current)
//      near the top of <head>, BEFORE the block that currently defines
//      window.storage.
//   2. Set window.ATD_SUPABASE_URL and window.ATD_SUPABASE_ANON_KEY (see
//      SETUP.md for where to find these) — plain <script> globals is enough
//      for a pilot; nothing secret is exposed since RLS is what enforces
//      access, not this key.
//   3. Replace the existing `window.storage = { ... }` block in
//      atendify.html with a single line: `window.storage = ATDBackend;`
//      (this file assigns itself to `window.ATDBackend`).
//   4. Leave the OLD localStorage-based object in place, commented out nearby,
//      as a fallback for offline demo/dev use — see ATDBackend.isConfigured()
//      below, which callers can check to decide which mode they're in.
//
// This file intentionally does NOT touch atendify.html directly yet — there
// is no live Supabase project to test against, and this app has no
// regression-test safety net. Wire it in as its own tested change once a
// project exists (see SETUP.md, step "Hand back to Claude").
// ============================================================================

(function () {
  'use strict';

  var SUPABASE_URL = window.ATD_SUPABASE_URL || null;
  var SUPABASE_ANON_KEY = window.ATD_SUPABASE_ANON_KEY || null;
  var TABLE = 'kv_store';
  var BUCKET = 'application-files';

  // Large-file fields that today are stored inline as base64 data URLs
  // inside the JSON value (see buildApplicationRecord / the upload handlers
  // in atendify.html). Moving just these to Supabase Storage removes the
  // localStorage-quota risk without touching any call site: get()/set()
  // rehydrate and offload transparently below.
  var FILE_FIELDS_BY_PREFIX = {
    applicationPhotoId: ['fileData'],
    applicationFlier: ['fileData'],
    applicationLogo: ['fileData'],
    applicationOwnership: ['fileData'],
    applicationFeeReceipt: ['fileData'],
    applicationPaymentReceipt: ['fileData'],
    applicationAdditionalPaymentReceipt: ['fileData'],
    jcfApplicationFiles: ['photoIdFileData', 'flyerFileData', 'permissionLetterFileData']
  };
  // Only offload a field to Storage once it's actually large enough that
  // localStorage-style inlining was the problem — small values just stay
  // in the jsonb column, which is simpler and one fewer round trip.
  var OFFLOAD_THRESHOLD_BYTES = 100 * 1024;

  var client = null;
  if (SUPABASE_URL && SUPABASE_ANON_KEY && window.supabase && window.supabase.createClient) {
    client = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  }

  function resolved(v) { return Promise.resolve(v); }
  function prefixOf(key) { return key.split(':')[0]; }

  async function storagePath(key, field) {
    // e.g. "applicationPhotoId:APP-2026-004" + "fileData"
    //   -> "applicationPhotoId/<ownerUid>/APP-2026-004/fileData.bin"
    // The owner-uid segment lets the storage RLS policy in
    // supabase_schema.sql scope access without re-deriving muniId from the
    // path; see that file's storage policies for why.
    var rest = key.slice(key.indexOf(':') + 1);
    var u = await client.auth.getUser();
    var uid = (u.data && u.data.user) ? u.data.user.id : 'anon';
    return prefixOf(key) + '/' + uid + '/' + rest + '/' + field + '.bin';
  }

  function dataUrlToBlob(dataUrl) {
    var parts = dataUrl.split(',');
    var meta = parts[0].match(/data:(.*?)(;base64)?$/);
    var mime = (meta && meta[1]) || 'application/octet-stream';
    var binary = atob(parts[1]);
    var bytes = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return new Blob([bytes], { type: mime });
  }

  function blobToDataUrl(blob) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () { resolve(reader.result); };
      reader.onerror = function () { reject(new Error('read failed')); };
      reader.readAsDataURL(blob);
    });
  }

  async function offloadLargeFields(key, obj) {
    var fields = FILE_FIELDS_BY_PREFIX[prefixOf(key)];
    if (!fields || !client) return obj;
    var out = Object.assign({}, obj);
    for (var i = 0; i < fields.length; i++) {
      var f = fields[i];
      var val = out[f];
      if (typeof val === 'string' && val.indexOf('data:') === 0 && val.length > OFFLOAD_THRESHOLD_BYTES) {
        var path = await storagePath(key, f);
        var blob = dataUrlToBlob(val);
        var up = await client.storage.from(BUCKET).upload(path, blob, { upsert: true, contentType: blob.type });
        if (!up.error) {
          out[f] = { __storageRef: path, __mime: blob.type };
        }
        // On upload failure, fall through and keep the inline value rather
        // than silently losing the file — same "fail safe, not silent" rule
        // the rest of this app already follows for uploads.
      }
    }
    return out;
  }

  async function rehydrateLargeFields(obj) {
    if (!obj || typeof obj !== 'object' || !client) return obj;
    var out = Object.assign({}, obj);
    var keys = Object.keys(out);
    for (var i = 0; i < keys.length; i++) {
      var f = keys[i];
      var val = out[f];
      if (val && typeof val === 'object' && val.__storageRef) {
        var dl = await client.storage.from(BUCKET).download(val.__storageRef);
        if (!dl.error) {
          out[f] = await blobToDataUrl(dl.data);
        } else {
          out[f] = null;
        }
      }
    }
    return out;
  }

  var ATDBackend = {
    isConfigured: function () { return !!client; },

    get: async function (key) {
      if (!client) return resolved({ value: undefined });
      try {
        var res = await client.from(TABLE).select('value').eq('key', key).maybeSingle();
        if (res.error || !res.data) return resolved({ value: undefined });
        var rehydrated = await rehydrateLargeFields(res.data.value);
        return resolved({ value: JSON.stringify(rehydrated) });
      } catch (e) {
        return resolved({ value: undefined });
      }
    },

    set: async function (key, value /* extra args ignored, matches current shim */) {
      if (!client) return Promise.reject(new Error('Backend not configured'));
      try {
        var parsed = JSON.parse(value);
        var offloaded = await offloadLargeFields(key, parsed);
        var res = await client.from(TABLE).upsert({ key: key, value: offloaded }, { onConflict: 'key' });
        if (res.error) return Promise.reject(res.error);
        return resolved({ ok: true });
      } catch (e) {
        return Promise.reject(e);
      }
    },

    delete: async function (key) {
      if (!client) return resolved({ ok: true });
      try {
        await client.from(TABLE).delete().eq('key', key);
      } catch (e) { /* mirror the old shim: swallow and report ok */ }
      return resolved({ ok: true });
    },

    list: async function (prefix) {
      if (!client) return resolved({ keys: [] });
      try {
        var q = client.from(TABLE).select('key');
        if (prefix) q = q.like('key', prefix + '%');
        var res = await q;
        if (res.error || !res.data) return resolved({ keys: [] });
        return resolved({ keys: res.data.map(function (r) { return r.key; }) });
      } catch (e) {
        return resolved({ keys: [] });
      }
    },

    // ---- Auth helpers, for the phase-1b login rewrite (not wired in yet) ----
    // Every portal's login function today checks a hardcoded/seeded password
    // client-side. Moving to real auth means each one calls signIn() here
    // instead, then reads the person's role/agency/permissions from
    // getProfile() rather than from a seeded local object.
    signIn: function (email, password) {
      if (!client) return Promise.reject(new Error('Backend not configured'));
      return client.auth.signInWithPassword({ email: email, password: password });
    },
    signUp: function (email, password) {
      if (!client) return Promise.reject(new Error('Backend not configured'));
      return client.auth.signUp({ email: email, password: password });
    },
    signOut: function () {
      if (!client) return resolved();
      return client.auth.signOut();
    },
    getProfile: async function () {
      if (!client) return null;
      var u = await client.auth.getUser();
      if (!u.data || !u.data.user) return null;
      var res = await client.from('profiles').select('*').eq('id', u.data.user.id).maybeSingle();
      return res.data || null;
    },

    // Pre-authorizes an email for a staff role (muni officer or JCF staff)
    // before that person has signed up. See supabase_schema.sql's
    // atd_handle_new_user trigger, which reads this table by email at
    // signup time to assign the right role/agency/branch/permissions
    // instead of defaulting to a public 'poa' applicant account.
    inviteStaff: async function (invite) {
      if (!client) return { error: new Error('Backend not configured') };
      return client.from('staff_invites').upsert({
        email: (invite.email || '').toLowerCase(),
        role: invite.role,
        agency_id: invite.agency_id || null,
        jcf_branch_id: invite.jcf_branch_id || null,
        permissions: invite.permissions || {},
        display_name: invite.display_name || null
      }, { onConflict: 'email' });
    }
  };

  window.ATDBackend = ATDBackend;
})();
