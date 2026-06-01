import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

import {
  RELAY_STATE_ARCHIVE_MUTATION_GRACE_MS,
  RELAY_STATE_CHANGE_RETENTION,
  RELAY_STATE_DB_FILE,
  RELAY_STATE_SCHEMA_VERSION,
} from "./dock-relay-constants.mjs";
import {
  ARCHIVE_VIEW,
  DOCK_VIEW,
  activityOrderKey,
  archiveOrderKey,
  normalizeStoredCard,
} from "./dock-relay-state-views.mjs";
import {
  HUMAN_APP_FACING_THREAD_SQL,
  HUMAN_APP_FACING_THREAD_SQL_FOR_ALIAS,
  deleteRejectedLiveLeases,
  deleteRejectedThreadCards,
  humanAppFacingStateCounts,
} from "./dock-relay-state-store-human-filter.mjs";

function nowISOString() {
  return new Date().toISOString();
}

function nowMs() {
  return Date.now();
}

function dateMs(value) {
  const parsed = Date.parse(value || "");
  return Number.isFinite(parsed) ? parsed : null;
}

function isFreshLocalArchiveMutation(row, atMs) {
  if (!row || row.archive_state !== "archived" || row.freshness_status !== "stale") {
    return false;
  }
  const updatedAtMs = dateMs(row.updated_at);
  if (updatedAtMs === null) {
    return false;
  }
  return atMs - updatedAtMs >= 0
    && atMs - updatedAtMs <= RELAY_STATE_ARCHIVE_MUTATION_GRACE_MS;
}

function sortedJSONString(value) {
  return JSON.stringify(sortJSON(value));
}

function sortJSON(value) {
  if (Array.isArray(value)) {
    return value.map(sortJSON);
  }
  if (value && typeof value === "object") {
    return Object.keys(value).sort().reduce((result, key) => {
      result[key] = sortJSON(value[key]);
      return result;
    }, {});
  }
  return value;
}

function stateDatabasePath(config) {
  if (config.relayStateDatabasePath) {
    return config.relayStateDatabasePath;
  }
  return path.resolve(process.cwd(), RELAY_STATE_DB_FILE);
}

function ensureParentDir(databasePath) {
  if (!databasePath || databasePath === ":memory:") {
    return;
  }
  fs.mkdirSync(path.dirname(databasePath), { recursive: true });
}

function boolInt(value) {
  return value ? 1 : 0;
}

function nullable(value) {
  return value === undefined ? null : value;
}

class RelayStateStore {
  constructor(config = {}) {
    this.config = config;
    this.databasePath = stateDatabasePath(config);
    ensureParentDir(this.databasePath);
    // SQLite stores relay-owned app-server projections; Codex remains the durable thread-history source.
    this.db = new DatabaseSync(this.databasePath);
    this.db.exec("PRAGMA journal_mode = WAL");
    this.db.exec("PRAGMA foreign_keys = ON");
    this.migrate();
    this.pruneForeignHosts();
  }

  migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS hosts (
        host_id TEXT PRIMARY KEY,
        display_name TEXT,
        endpoint TEXT,
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS threads (
        host_id TEXT NOT NULL,
        thread_id TEXT NOT NULL,
        dock_id TEXT NOT NULL,
        logical_host_id TEXT,
        backend_session_id TEXT,
        host_display_name TEXT,
        host_endpoint TEXT,
        order_key TEXT,
        activity_at TEXT,
        activity_at_ms INTEGER,
        display_summary TEXT,
        title TEXT,
        status TEXT NOT NULL,
        lane TEXT,
        repository TEXT,
        working_directory TEXT,
        branch TEXT,
        updated_at_ms INTEGER,
        source_kind TEXT,
        relationship TEXT,
        forked_from_id TEXT,
        archive_state TEXT NOT NULL DEFAULT 'active',
        completeness TEXT NOT NULL DEFAULT 'complete',
        summary_source TEXT,
        activity_proof_status TEXT NOT NULL DEFAULT 'unknown',
        activity_proof_source TEXT,
        activity_proof_checked_at TEXT,
        active_scope_present INTEGER NOT NULL DEFAULT 0,
        archived_scope_present INTEGER NOT NULL DEFAULT 0,
        freshness_status TEXT NOT NULL DEFAULT 'unknown',
        last_seen_at TEXT,
        updated_at TEXT NOT NULL,
        raw_json TEXT,
        PRIMARY KEY (host_id, thread_id),
        FOREIGN KEY (host_id) REFERENCES hosts(host_id) ON DELETE CASCADE
      );

      CREATE TABLE IF NOT EXISTS sync_scopes (
        host_id TEXT NOT NULL,
        scope TEXT NOT NULL,
        archived INTEGER NOT NULL,
        source_scope TEXT NOT NULL,
        complete INTEGER NOT NULL,
        generation INTEGER NOT NULL DEFAULT 0,
        last_attempt_at TEXT NOT NULL,
        last_sync_at TEXT,
        last_error TEXT,
        PRIMARY KEY (host_id, scope)
      );

      CREATE TABLE IF NOT EXISTS live_leases (
        host_id TEXT NOT NULL,
        thread_id TEXT NOT NULL,
        endpoint_label TEXT,
        endpoint_url TEXT,
        backend_session_id TEXT,
        status TEXT NOT NULL,
        waiting_state TEXT,
        command_capability INTEGER NOT NULL DEFAULT 0,
        validation_at TEXT NOT NULL,
        validation_at_ms INTEGER NOT NULL,
        expires_at_ms INTEGER NOT NULL,
        expired_published_at TEXT,
        PRIMARY KEY (host_id, thread_id)
      );

      CREATE TABLE IF NOT EXISTS subscriptions (
        subscription_id TEXT PRIMARY KEY,
        view TEXT NOT NULL,
        host_id TEXT,
        cursor_seq INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS changes (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        view TEXT NOT NULL,
        host_id TEXT,
        thread_id TEXT,
        change_type TEXT NOT NULL,
        payload_json TEXT,
        created_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS conflicts (
        host_id TEXT NOT NULL,
        thread_id TEXT NOT NULL,
        field TEXT NOT NULL,
        details_json TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (host_id, thread_id, field)
      );

      CREATE TABLE IF NOT EXISTS turn_cache (
        host_id TEXT NOT NULL,
        thread_id TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        byte_count INTEGER NOT NULL,
        complete INTEGER NOT NULL,
        stop_reason TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (host_id, thread_id)
      );

      CREATE TABLE IF NOT EXISTS audit_runs (
        audit_id TEXT PRIMARY KEY,
        started_at TEXT NOT NULL,
        completed_at TEXT,
        status TEXT NOT NULL,
        summary_json TEXT
      );

      CREATE TABLE IF NOT EXISTS audit_findings (
        finding_id TEXT PRIMARY KEY,
        audit_id TEXT,
        host_id TEXT,
        thread_id TEXT,
        finding_type TEXT NOT NULL,
        details_json TEXT,
        created_at TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_threads_dock
        ON threads(host_id, active_scope_present, archive_state, order_key);
      CREATE INDEX IF NOT EXISTS idx_threads_archive
        ON threads(host_id, archive_state, order_key);
      CREATE INDEX IF NOT EXISTS idx_changes_view_seq
        ON changes(view, seq);
    `);
    this.ensureThreadColumns();
    this.ensureLiveLeaseColumns();
    // Card truth lives on stored thread rows. Remove the old decorative
    // provenance table so proof cannot drift away from the row the client sees.
    this.db.exec("DROP TABLE IF EXISTS thread_field_provenance");
    this.db.prepare(`
      INSERT OR IGNORE INTO schema_migrations (version, applied_at)
      VALUES (?, ?)
    `).run(RELAY_STATE_SCHEMA_VERSION, nowISOString());
    for (const obsoleteScope of ["active:dock", "active:default"]) {
      this.db.prepare("DELETE FROM sync_scopes WHERE scope = ?").run(obsoleteScope);
    }
  }

  ensureThreadColumns() {
    const columns = new Set(this.db.prepare("PRAGMA table_info(threads)").all().map((row) => row.name));
    const definitions = {
      logical_host_id: "TEXT",
      host_display_name: "TEXT",
      host_endpoint: "TEXT",
      order_key: "TEXT",
      activity_at: "TEXT",
      activity_at_ms: "INTEGER",
      display_summary: "TEXT",
      completeness: "TEXT NOT NULL DEFAULT 'complete'",
      summary_source: "TEXT",
      relationship: "TEXT",
      forked_from_id: "TEXT",
      activity_proof_status: "TEXT NOT NULL DEFAULT 'unknown'",
      activity_proof_source: "TEXT",
      activity_proof_checked_at: "TEXT",
    };
    for (const [column, definition] of Object.entries(definitions)) {
      if (!columns.has(column)) {
        this.db.exec(`ALTER TABLE threads ADD COLUMN ${column} ${definition}`);
      }
    }
  }

  ensureLiveLeaseColumns() {
    const columns = new Set(this.db.prepare("PRAGMA table_info(live_leases)").all().map((row) => row.name));
    const definitions = {
      expired_published_at: "TEXT",
    };
    for (const [column, definition] of Object.entries(definitions)) {
      if (!columns.has(column)) {
        this.db.exec(`ALTER TABLE live_leases ADD COLUMN ${column} ${definition}`);
      }
    }
  }

  pruneForeignHosts() {
    const hostID = this.config.hostId;
    if (!hostID) {
      return;
    }
    this.transaction(() => {
      this.db.prepare("DELETE FROM hosts WHERE host_id != ?").run(hostID);
      for (const table of [
        "threads",
        "sync_scopes",
        "live_leases",
        "conflicts",
        "turn_cache",
      ]) {
        this.db.prepare(`DELETE FROM ${table} WHERE host_id != ?`).run(hostID);
      }
      this.db.prepare("DELETE FROM subscriptions WHERE host_id IS NOT NULL AND host_id != ?").run(hostID);
      this.db.prepare("DELETE FROM changes WHERE host_id IS NOT NULL AND host_id != ?").run(hostID);
      this.db.prepare("DELETE FROM audit_findings WHERE host_id IS NOT NULL AND host_id != ?").run(hostID);
    });
  }

  close() {
    this.db.close();
  }

  transaction(fn) {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const result = fn();
      this.db.exec("COMMIT");
      return result;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  upsertHost(host, at = nowISOString()) {
    this.db.prepare(`
      INSERT INTO hosts (host_id, display_name, endpoint, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(host_id) DO UPDATE SET
        display_name = excluded.display_name,
        endpoint = excluded.endpoint,
        updated_at = excluded.updated_at
    `).run(host.id, nullable(host.displayName), nullable(host.endpoint), at);
  }

  currentSeq() {
    return this.db.prepare("SELECT COALESCE(MAX(seq), 0) AS seq FROM changes").get().seq || 0;
  }

  hostRows() {
    return this.db.prepare(`
      SELECT host_id AS id, host_id AS logicalHostID, display_name AS displayName, endpoint
      FROM hosts
      ORDER BY host_id ASC
    `).all();
  }

  freshnessForHost(hostID, { archived = null } = {}) {
    const scopeWhere = archived === null ? "" : " AND archived = ?";
    const scopeArgs = archived === null ? [hostID] : [hostID, boolInt(archived)];
    const rows = this.db.prepare(`
      SELECT complete, last_attempt_at, last_sync_at, last_error
      FROM sync_scopes
      WHERE host_id = ?
      ${scopeWhere}
    `).all(...scopeArgs);
    if (rows.length === 0) {
      return {
        status: "unknown",
        lastAttemptAt: null,
        lastSyncAt: null,
        lastError: null,
      };
    }
    const failed = rows.find((row) => row.complete === 0);
    const presenceColumn = archived === true
      ? "archived_scope_present"
      : (archived === false ? "active_scope_present" : "(active_scope_present = 1 OR archived_scope_present = 1)");
    const unprovenCards = this.db.prepare(`
      SELECT COUNT(*) AS count
      FROM threads
      WHERE host_id = ?
        AND ${archived === null ? presenceColumn : `${presenceColumn} = 1`}
        AND (activity_proof_status != 'proven' OR completeness != 'complete' OR freshness_status != 'fresh')
    `).get(hostID).count;
    const latestAttempt = rows.map((row) => row.last_attempt_at).filter(Boolean).sort().at(-1) || null;
    const latestSync = rows.map((row) => row.last_sync_at).filter(Boolean).sort().at(-1) || null;
    return {
      status: failed || Number(unprovenCards || 0) > 0 ? "stale" : "fresh",
      lastAttemptAt: latestAttempt,
      lastSyncAt: latestSync,
      lastError: failed?.last_error || (Number(unprovenCards || 0) > 0 ? "card activity proof incomplete" : null),
    };
  }

  cardTruthCompleteForHost(hostID, { archived = false } = {}) {
    const archivePredicate = archived
      ? "archive_state = 'archived' AND archived_scope_present = 1"
      : "active_scope_present = 1 AND archive_state != 'archived'";
    const row = this.db.prepare(`
      SELECT COUNT(*) AS count
      FROM threads
      WHERE host_id = ?
        AND ${archivePredicate}
        AND ${HUMAN_APP_FACING_THREAD_SQL}
        AND (activity_proof_status != 'proven' OR completeness != 'complete' OR freshness_status != 'fresh')
    `).get(hostID);
    return Number(row?.count || 0) === 0;
  }

  listDockCards({ hostID, offset = 0, limit = null } = {}) {
    const params = [];
    let countWhere = `${HUMAN_APP_FACING_THREAD_SQL} AND active_scope_present = 1 AND archive_state != 'archived'`;
    let rowWhere = `${HUMAN_APP_FACING_THREAD_SQL_FOR_ALIAS} AND t.active_scope_present = 1 AND t.archive_state != 'archived'`;
    if (hostID) {
      countWhere += " AND host_id = ?";
      rowWhere += " AND t.host_id = ?";
      params.push(hostID);
    }
    const totalRows = this.db.prepare(`SELECT COUNT(*) AS count FROM threads WHERE ${countWhere}`).get(...params).count;
    const queryParams = [...params];
    let limitClause = "";
    if (limit !== null && limit !== undefined) {
      limitClause = " LIMIT ? OFFSET ?";
      queryParams.push(Number(limit), Number(offset || 0));
    }
    const rows = this.db.prepare(`
      SELECT t.*
      FROM threads t
      WHERE ${rowWhere}
      ORDER BY t.order_key ASC, t.thread_id ASC
      ${limitClause}
    `).all(...queryParams);
    return {
      totalRows,
      cards: rows.map(normalizeStoredCard).filter(Boolean),
    };
  }

  listArchiveCards({ hostID, offset = 0, limit = null } = {}) {
    const params = [];
    let where = `${HUMAN_APP_FACING_THREAD_SQL} AND archive_state = 'archived' AND archived_scope_present = 1`;
    if (hostID) {
      where += " AND host_id = ?";
      params.push(hostID);
    }
    const totalRows = this.db.prepare(`SELECT COUNT(*) AS count FROM threads WHERE ${where}`).get(...params).count;
    const queryParams = [...params];
    let limitClause = "";
    if (limit !== null && limit !== undefined) {
      limitClause = " LIMIT ? OFFSET ?";
      queryParams.push(Number(limit), Number(offset || 0));
    }
    const rows = this.db.prepare(`
      SELECT *
      FROM threads
      WHERE ${where}
      ORDER BY order_key ASC, thread_id ASC
      ${limitClause}
    `).all(...queryParams);
    return {
      totalRows,
      cards: rows.map(normalizeStoredCard).filter(Boolean),
    };
  }

  applyDockReconciliation({ host, cards, scopes = [], complete = true, error = null, previousCards = null }) {
    const atMs = nowMs();
    const at = new Date(atMs).toISOString();
    return this.transaction(() => {
      this.upsertHost(host, at);
      const previousRows = Array.isArray(previousCards)
        ? previousCards
        : this.listDockCards({ hostID: host.id }).cards;
      const previousByID = new Map(previousRows.map((row) => [row.id, row]));
      const existingRows = this.db.prepare(`
        SELECT thread_id, archive_state, freshness_status, updated_at
        FROM threads
        WHERE host_id = ?
      `).all(host.id);
      const existingByThreadID = new Map(existingRows.map((row) => [row.thread_id, row]));
      const nextByID = new Map();
      const upsertCards = [];
      const deleteCardIDs = [];

      cards.forEach((card) => {
        const existing = existingByThreadID.get(card.threadID);
        if (isFreshLocalArchiveMutation(existing, atMs)) {
          return;
        }
        const cardWithOrder = {
          ...card,
          orderKey: card.orderKey || activityOrderKey(card.activityAtMs || Date.now(), card.threadID),
          archiveState: "active",
        };
        nextByID.set(cardWithOrder.id, cardWithOrder);
        const previous = previousByID.get(cardWithOrder.id);
        if (sortedJSONString(previous) !== sortedJSONString(cardWithOrder)) {
          upsertCards.push(cardWithOrder);
        }
        this.upsertThreadCard(host.id, cardWithOrder, {
          archiveState: "active",
          activeScopePresent: true,
          at,
        });
      });

      if (complete) {
        for (const previous of previousRows) {
          if (!nextByID.has(previous.id)) {
            deleteCardIDs.push(previous.id);
            this.markThreadInactive(host.id, previous.threadID, at);
          }
        }
      }

      for (const scope of scopes) {
        this.recordSyncScope(host.id, scope, at);
      }
      if (scopes.length === 0) {
        this.recordSyncScope(host.id, {
          name: "active:interactiveDefault",
          archived: false,
          sourceScope: "interactiveDefault",
          complete,
          error,
        }, at);
      }

      const seq = this.recordChange({
        view: DOCK_VIEW,
        hostID: host.id,
        changeType: "dock-reconcile",
        payload: {
          upsertCount: upsertCards.length,
          deleteCount: deleteCardIDs.length,
          complete,
        },
        at,
      });
      this.pruneChanges();
      return { seq, upsertCards, deleteCardIDs };
    });
  }

  applyArchiveReconciliation({ host, cards, complete = true, error = null, previousCards = null }) {
    const at = nowISOString();
    return this.transaction(() => {
      this.upsertHost(host, at);
      const previousRows = Array.isArray(previousCards)
        ? previousCards
        : this.listArchiveCards({ hostID: host.id }).cards;
      const previousByID = new Map(previousRows.map((row) => [row.id, row]));
      const nextByID = new Map();
      const upsertCards = [];
      const deleteCardIDs = [];

      cards.forEach((card, index) => {
        const cardWithOrder = {
          ...card,
          orderKey: card.orderKey || archiveOrderKey(card.activityAtMs || Date.now(), card.threadID),
          archiveState: "archived",
        };
        nextByID.set(cardWithOrder.id, cardWithOrder);
        const previous = previousByID.get(cardWithOrder.id);
        if (sortedJSONString(previous) !== sortedJSONString(cardWithOrder)) {
          upsertCards.push(cardWithOrder);
        }
        this.upsertThreadCard(host.id, cardWithOrder, {
          archiveState: "archived",
          activeScopePresent: false,
          archivedScopePresent: true,
          at,
        });
      });

      if (complete) {
        for (const previous of previousRows) {
          if (!nextByID.has(previous.id)) {
            deleteCardIDs.push(previous.id);
            this.markThreadNotArchived(host.id, previous.threadID, at);
          }
        }
      }

      this.recordSyncScope(host.id, {
        name: "archived:interactiveDefault",
        archived: true,
        sourceScope: "interactiveDefault",
        complete,
        error,
      }, at);

      const seq = this.recordChange({
        view: ARCHIVE_VIEW,
        hostID: host.id,
        changeType: "archive-reconcile",
        payload: {
          upsertCount: upsertCards.length,
          deleteCount: deleteCardIDs.length,
          complete,
        },
        at,
      });
      this.pruneChanges();
      return { seq, upsertCards, deleteCardIDs };
    });
  }

  upsertThreadCard(hostID, card, {
    archiveState = "active",
    activeScopePresent = true,
    archivedScopePresent = false,
    at = nowISOString(),
  } = {}) {
    // Stored threads are the only card source emitted to Swift. Activity proof
    // is stored beside the card row, and live lease status must be folded before
    // this write rather than overlaid afterward.
    this.db.prepare(`
      INSERT INTO threads (
        host_id, thread_id, dock_id, logical_host_id, backend_session_id,
        host_display_name, host_endpoint, order_key, activity_at, activity_at_ms,
        display_summary, title, status, lane, repository, working_directory,
        branch, updated_at_ms, source_kind, relationship, forked_from_id, archive_state, completeness,
        summary_source, activity_proof_status, activity_proof_source, activity_proof_checked_at,
        active_scope_present, archived_scope_present,
        freshness_status, last_seen_at, updated_at, raw_json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(host_id, thread_id) DO UPDATE SET
        dock_id = excluded.dock_id,
        logical_host_id = excluded.logical_host_id,
        backend_session_id = excluded.backend_session_id,
        host_display_name = excluded.host_display_name,
        host_endpoint = excluded.host_endpoint,
        order_key = excluded.order_key,
        activity_at = excluded.activity_at,
        activity_at_ms = excluded.activity_at_ms,
        display_summary = excluded.display_summary,
        title = excluded.title,
        status = excluded.status,
        lane = excluded.lane,
        repository = excluded.repository,
        working_directory = excluded.working_directory,
        branch = excluded.branch,
        updated_at_ms = excluded.updated_at_ms,
        source_kind = excluded.source_kind,
        relationship = excluded.relationship,
        forked_from_id = excluded.forked_from_id,
        archive_state = excluded.archive_state,
        completeness = excluded.completeness,
        summary_source = excluded.summary_source,
        activity_proof_status = excluded.activity_proof_status,
        activity_proof_source = excluded.activity_proof_source,
        activity_proof_checked_at = excluded.activity_proof_checked_at,
        active_scope_present = excluded.active_scope_present,
        archived_scope_present = excluded.archived_scope_present,
        freshness_status = excluded.freshness_status,
        last_seen_at = excluded.last_seen_at,
        updated_at = excluded.updated_at,
        raw_json = excluded.raw_json
    `).run(
      hostID,
      card.threadID,
      card.id,
      nullable(card.logicalHostID),
      nullable(card.backendSessionID),
      nullable(card.hostDisplayName),
      nullable(card.hostEndpoint),
      nullable(card.orderKey),
      nullable(card.activityAt),
      nullable(card.activityAtMs),
      nullable(card.displaySummary),
      nullable(card.title),
      card.status || "unknown",
      nullable(card.lane),
      nullable(card.repository),
      nullable(card.workingDirectory),
      nullable(card.branch),
      nullable(card.activityAtMs),
      nullable(card.sourceKind),
      nullable(card.relationship),
      nullable(card.forkedFromID),
      archiveState,
      nullable(card.completeness || "complete"),
      nullable(card.summarySource),
      nullable(card.activityProofStatus || (card.completeness === "complete" && card.freshness === "fresh" ? "proven" : "unproven")),
      nullable(card.activityProofSource || null),
      nullable(card.activityProofCheckedAt || null),
      boolInt(activeScopePresent),
      boolInt(archivedScopePresent),
      card.freshness || "fresh",
      at,
      at,
      JSON.stringify(card),
    );
  }

  markThreadInactive(hostID, threadID, at = nowISOString()) {
    this.db.prepare(`
      UPDATE threads
      SET active_scope_present = 0, updated_at = ?
      WHERE host_id = ? AND thread_id = ?
    `).run(at, hostID, threadID);
  }

  markThreadNotArchived(hostID, threadID, at = nowISOString()) {
    this.db.prepare(`
      UPDATE threads
      SET archive_state = 'active', archived_scope_present = 0, updated_at = ?
      WHERE host_id = ? AND thread_id = ?
    `).run(at, hostID, threadID);
  }

  deleteRejectedThreadCards(hostID = null) {
    return deleteRejectedThreadCards(this.db, hostID);
  }

  deleteRejectedLiveLeases(hostID = null) {
    return deleteRejectedLiveLeases(this.db, hostID);
  }

  cardForThread({ hostID, threadID }) {
    const row = this.db.prepare(`
      SELECT t.*
      FROM threads t
      WHERE t.host_id = ? AND t.thread_id = ?
        AND ${HUMAN_APP_FACING_THREAD_SQL_FOR_ALIAS}
      LIMIT 1
    `).get(hostID, threadID);
    return normalizeStoredCard(row);
  }

  upsertLiveLease(hostID, lease, at = nowISOString()) {
    this.db.prepare(`
      INSERT INTO live_leases (
        host_id, thread_id, endpoint_label, endpoint_url, backend_session_id,
        status, waiting_state, command_capability, validation_at,
        validation_at_ms, expires_at_ms, expired_published_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
      ON CONFLICT(host_id, thread_id) DO UPDATE SET
        endpoint_label = excluded.endpoint_label,
        endpoint_url = excluded.endpoint_url,
        backend_session_id = excluded.backend_session_id,
        status = excluded.status,
        waiting_state = excluded.waiting_state,
        command_capability = excluded.command_capability,
        validation_at = excluded.validation_at,
        validation_at_ms = excluded.validation_at_ms,
        expires_at_ms = excluded.expires_at_ms,
        expired_published_at = NULL
    `).run(
      hostID,
      lease.threadID,
      nullable(lease.endpointLabel),
      nullable(lease.endpointUrl),
      nullable(lease.backendSessionID),
      lease.status || "unknown",
      nullable(lease.waitingState),
      boolInt(lease.commandCapability),
      at,
      Number(lease.validationAtMs || nowMs()),
      Number(lease.expiresAtMs || (nowMs() + 5_000)),
    );
  }

  markLiveLeaseExpiryPublished(hostID, threadID, at = nowISOString()) {
    this.db.prepare(`
      UPDATE live_leases
      SET expired_published_at = COALESCE(expired_published_at, ?)
      WHERE host_id = ? AND thread_id = ?
    `).run(at, hostID, threadID);
  }

  nextUnpublishedLiveLeaseExpiryMs(hostID, atMs = nowMs()) {
    const row = this.db.prepare(`
      SELECT MIN(expires_at_ms) AS expires_at_ms
      FROM live_leases
      WHERE host_id = ?
        AND expires_at_ms >= ?
        AND expired_published_at IS NULL
        AND EXISTS (
          SELECT 1
          FROM threads t
          WHERE t.host_id = live_leases.host_id
            AND t.thread_id = live_leases.thread_id
            AND ${HUMAN_APP_FACING_THREAD_SQL_FOR_ALIAS}
        )
    `).get(hostID, Number(atMs));
    const expiresAtMs = Number(row?.expires_at_ms || 0);
    return Number.isFinite(expiresAtMs) && expiresAtMs > 0 ? expiresAtMs : null;
  }

  recordSyncScope(hostID, scope, at = nowISOString()) {
    const name = scope.name || `${scope.archived ? "archived" : "active"}:${scope.sourceScope || "unknown"}`;
    const current = this.db.prepare(`
      SELECT generation FROM sync_scopes WHERE host_id = ? AND scope = ?
    `).get(hostID, name);
    this.db.prepare(`
      INSERT INTO sync_scopes (
        host_id, scope, archived, source_scope, complete, generation,
        last_attempt_at, last_sync_at, last_error
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(host_id, scope) DO UPDATE SET
        archived = excluded.archived,
        source_scope = excluded.source_scope,
        complete = excluded.complete,
        generation = excluded.generation,
        last_attempt_at = excluded.last_attempt_at,
        last_sync_at = excluded.last_sync_at,
        last_error = excluded.last_error
    `).run(
      hostID,
      name,
      boolInt(scope.archived),
      scope.sourceScope || "unknown",
      boolInt(scope.complete),
      Number(current?.generation || 0) + 1,
      at,
      scope.complete ? at : null,
      scope.error || null,
    );
  }

  markScopeStale(hostID, scopeName, error) {
    const at = nowISOString();
    const archived = String(scopeName || "").startsWith("archived:");
    this.db.prepare(`
      INSERT INTO sync_scopes (
        host_id, scope, archived, source_scope, complete, generation,
        last_attempt_at, last_sync_at, last_error
      )
      VALUES (?, ?, ?, ?, 0, 1, ?, NULL, ?)
      ON CONFLICT(host_id, scope) DO UPDATE SET
        archived = excluded.archived,
        complete = 0,
        last_attempt_at = excluded.last_attempt_at,
        last_error = excluded.last_error
    `).run(hostID, scopeName, boolInt(archived), scopeName, at, error?.message || String(error));
    this.recordChange({
      view: archived ? ARCHIVE_VIEW : DOCK_VIEW,
      hostID,
      changeType: "scope-stale",
      payload: { scopeName },
      at,
    });
    this.pruneChanges();
  }

  recordChange({
    view,
    hostID = null,
    threadID = null,
    changeType,
    payload = null,
    at = nowISOString(),
  }) {
    const result = this.db.prepare(`
      INSERT INTO changes (view, host_id, thread_id, change_type, payload_json, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(view, hostID, threadID, changeType, payload ? JSON.stringify(payload) : null, at);
    return Number(result.lastInsertRowid);
  }

  pruneChanges(limit = RELAY_STATE_CHANGE_RETENTION) {
    this.db.prepare(`
      DELETE FROM changes
      WHERE seq NOT IN (
        SELECT seq FROM changes ORDER BY seq DESC LIMIT ?
      )
    `).run(limit);
  }

  stateCounts() {
    const counts = humanAppFacingStateCounts(this.db, nowMs());
    const scopes = this.db.prepare(`
      SELECT COUNT(*) AS count FROM sync_scopes WHERE complete = 0
    `).get().count;
    return {
      active: counts.active,
      archived: counts.archived,
      live: counts.live,
      spawned: 0,
      stale: counts.stale,
      incomplete: Number(scopes || 0),
      conflict: 0,
    };
  }

  syncScopes() {
    return this.db.prepare(`
      SELECT host_id AS hostID, scope, archived, source_scope AS sourceScope,
             complete, generation, last_attempt_at AS lastAttemptAt,
             last_sync_at AS lastSyncAt, last_error AS lastError
      FROM sync_scopes
      ORDER BY host_id ASC, scope ASC
    `).all();
  }

  dbHealth() {
    const walPath = `${this.databasePath}-wal`;
    const shmPath = `${this.databasePath}-shm`;
    return {
      path: this.databasePath,
      schemaVersion: RELAY_STATE_SCHEMA_VERSION,
      currentSeq: this.currentSeq(),
      walPresent: this.databasePath !== ":memory:" && fs.existsSync(walPath),
      shmPresent: this.databasePath !== ":memory:" && fs.existsSync(shmPath),
      sizeBytes: this.databasePath !== ":memory:" && fs.existsSync(this.databasePath)
        ? fs.statSync(this.databasePath).size
        : null,
    };
  }
}

function relayStateStoreForConfig(config) {
  if (!config.relayStateStore) {
    config.relayStateStore = new RelayStateStore(config);
  }
  return config.relayStateStore;
}

export {
  RelayStateStore,
  relayStateStoreForConfig,
  stateDatabasePath,
};
