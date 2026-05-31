const HUMAN_APP_FACING_THREAD_SQL = "lane = 'human' AND source_kind = 'human'";
const HUMAN_APP_FACING_THREAD_SQL_FOR_ALIAS = "t.lane = 'human' AND t.source_kind = 'human'";
const REJECTED_APP_FACING_THREAD_SQL = "lane IS NOT 'human' OR source_kind IS NOT 'human'";

function deleteRejectedThreadCards(db, hostID = null) {
  const params = [];
  let where = REJECTED_APP_FACING_THREAD_SQL;
  if (hostID) {
    where += " AND host_id = ?";
    params.push(hostID);
  }
  const result = db.prepare(`
    DELETE FROM threads
    WHERE ${where}
  `).run(...params);
  return { deleted: Number(result.changes || 0) };
}

function deleteRejectedLiveLeases(db, hostID = null) {
  const params = [];
  let where = `
    NOT EXISTS (
      SELECT 1
      FROM threads t
      WHERE t.host_id = live_leases.host_id
        AND t.thread_id = live_leases.thread_id
        AND ${HUMAN_APP_FACING_THREAD_SQL_FOR_ALIAS}
    )
  `;
  if (hostID) {
    where += " AND live_leases.host_id = ?";
    params.push(hostID);
  }
  const result = db.prepare(`
    DELETE FROM live_leases
    WHERE ${where}
  `).run(...params);
  return { deleted: Number(result.changes || 0) };
}

function humanAppFacingStateCounts(db, atMs) {
  const threadCounts = db.prepare(`
    SELECT
      SUM(CASE WHEN ${HUMAN_APP_FACING_THREAD_SQL} AND active_scope_present = 1 AND archive_state != 'archived' THEN 1 ELSE 0 END) AS active,
      SUM(CASE WHEN ${HUMAN_APP_FACING_THREAD_SQL} AND archive_state = 'archived' THEN 1 ELSE 0 END) AS archived,
      SUM(CASE WHEN ${HUMAN_APP_FACING_THREAD_SQL} AND freshness_status = 'stale' THEN 1 ELSE 0 END) AS stale
    FROM threads
  `).get();
  const live = db.prepare(`
    SELECT COUNT(*) AS count
    FROM live_leases
    WHERE expires_at_ms >= ?
      AND EXISTS (
        SELECT 1
        FROM threads t
        WHERE t.host_id = live_leases.host_id
          AND t.thread_id = live_leases.thread_id
          AND ${HUMAN_APP_FACING_THREAD_SQL_FOR_ALIAS}
      )
  `).get(atMs).count;
  return {
    active: Number(threadCounts.active || 0),
    archived: Number(threadCounts.archived || 0),
    live: Number(live || 0),
    stale: Number(threadCounts.stale || 0),
  };
}

export {
  HUMAN_APP_FACING_THREAD_SQL,
  HUMAN_APP_FACING_THREAD_SQL_FOR_ALIAS,
  deleteRejectedLiveLeases,
  deleteRejectedThreadCards,
  humanAppFacingStateCounts,
};
