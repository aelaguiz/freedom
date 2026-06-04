function nowISOString() {
  return new Date().toISOString();
}

function outboundUserMessageFromRow(row) {
  return {
    hostID: row.host_id,
    threadID: row.thread_id,
    clientUserMessageID: row.client_user_message_id,
    inputJSON: row.input_json,
    inputHash: row.input_hash,
    state: row.state,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    upstreamEndpointUrl: row.upstream_endpoint_url,
    upstreamMethod: row.upstream_method,
    upstreamRequestID: row.upstream_request_id,
    codexTurnID: row.codex_turn_id,
    codexItemID: row.codex_item_id,
    lastErrorCode: row.last_error_code,
    lastErrorMessage: row.last_error_message,
  };
}

function ensureOutboundUserMessageStoreSchema(db) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS outbound_user_messages (
      host_id TEXT NOT NULL,
      thread_id TEXT NOT NULL,
      client_user_message_id TEXT NOT NULL,
      input_json TEXT NOT NULL,
      input_hash TEXT NOT NULL,
      state TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      upstream_endpoint_url TEXT,
      upstream_method TEXT,
      upstream_request_id TEXT,
      codex_turn_id TEXT,
      codex_item_id TEXT,
      last_error_code TEXT,
      last_error_message TEXT,
      PRIMARY KEY (host_id, thread_id, client_user_message_id)
    )
  `);
}

function pruneForeignOutboundUserMessages(db, hostID) {
  db.prepare("DELETE FROM outbound_user_messages WHERE host_id != ?").run(hostID);
}

class RelayOutboundUserMessageStore {
  constructor(db) {
    this.db = db;
    ensureOutboundUserMessageStoreSchema(db);
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

  messageForClientID(hostID, threadID, clientUserMessageID) {
    const row = this.db.prepare(`
      SELECT host_id, thread_id, client_user_message_id, input_json, input_hash,
             state, created_at, updated_at, upstream_endpoint_url,
             upstream_method, upstream_request_id, codex_turn_id, codex_item_id,
             last_error_code, last_error_message
      FROM outbound_user_messages
      WHERE host_id = ? AND thread_id = ? AND client_user_message_id = ?
    `).get(hostID, threadID, clientUserMessageID);
    return row ? outboundUserMessageFromRow(row) : null;
  }

  upsertAccepted({
    hostID,
    threadID,
    clientUserMessageID,
    inputJSON,
    inputHash,
    at = nowISOString(),
  }) {
    return this.transaction(() => {
      const existing = this.messageForClientID(hostID, threadID, clientUserMessageID);
      if (existing) {
        if (existing.inputHash !== inputHash) {
          return {
            status: "collision",
            row: existing,
          };
        }
        return {
          status: "existing",
          row: existing,
        };
      }
      this.db.prepare(`
        INSERT INTO outbound_user_messages (
          host_id, thread_id, client_user_message_id, input_json, input_hash,
          state, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, 'acceptedByRelay', ?, ?)
      `).run(hostID, threadID, clientUserMessageID, inputJSON, inputHash, at, at);
      return {
        status: "inserted",
        row: this.messageForClientID(hostID, threadID, clientUserMessageID),
      };
    });
  }

  markSubmitted({
    hostID,
    threadID,
    clientUserMessageID,
    upstreamEndpointUrl = null,
    upstreamMethod = null,
    upstreamRequestID = null,
    codexTurnID = null,
    codexItemID = null,
    at = nowISOString(),
  }) {
    this.db.prepare(`
      UPDATE outbound_user_messages
      SET state = 'submittedUpstream',
          updated_at = ?,
          upstream_endpoint_url = ?,
          upstream_method = ?,
          upstream_request_id = ?,
          codex_turn_id = COALESCE(?, codex_turn_id),
          codex_item_id = COALESCE(?, codex_item_id),
          last_error_code = NULL,
          last_error_message = NULL
      WHERE host_id = ? AND thread_id = ? AND client_user_message_id = ?
    `).run(
      at,
      upstreamEndpointUrl,
      upstreamMethod,
      upstreamRequestID,
      codexTurnID,
      codexItemID,
      hostID,
      threadID,
      clientUserMessageID,
    );
    return this.messageForClientID(hostID, threadID, clientUserMessageID);
  }

  markCanonicalObserved({
    hostID,
    threadID,
    clientUserMessageID,
    codexTurnID = null,
    codexItemID = null,
    at = nowISOString(),
  }) {
    this.db.prepare(`
      UPDATE outbound_user_messages
      SET state = 'canonicalObserved',
          updated_at = ?,
          codex_turn_id = COALESCE(?, codex_turn_id),
          codex_item_id = COALESCE(?, codex_item_id),
          last_error_code = NULL,
          last_error_message = NULL
      WHERE host_id = ? AND thread_id = ? AND client_user_message_id = ?
    `).run(at, codexTurnID, codexItemID, hostID, threadID, clientUserMessageID);
    return this.messageForClientID(hostID, threadID, clientUserMessageID);
  }

  markFailed({
    hostID,
    threadID,
    clientUserMessageID,
    state,
    errorCode = null,
    errorMessage = null,
    at = nowISOString(),
  }) {
    this.db.prepare(`
      UPDATE outbound_user_messages
      SET state = ?,
          updated_at = ?,
          last_error_code = ?,
          last_error_message = ?
      WHERE host_id = ? AND thread_id = ? AND client_user_message_id = ?
    `).run(state, at, errorCode, errorMessage, hostID, threadID, clientUserMessageID);
    return this.messageForClientID(hostID, threadID, clientUserMessageID);
  }
}

function outboundUserMessageStoreForConfig(config, stateStore) {
  if (!config.relayOutboundUserMessageStore) {
    config.relayOutboundUserMessageStore = new RelayOutboundUserMessageStore(stateStore.db);
  }
  return config.relayOutboundUserMessageStore;
}

export {
  RelayOutboundUserMessageStore,
  ensureOutboundUserMessageStoreSchema,
  outboundUserMessageStoreForConfig,
  pruneForeignOutboundUserMessages,
};
