-- ocs-preview-full.sql
-- Full transcript preview for a single session (text + reasoning + tool calls).
-- :sid is replaced by sed before sqlite3 runs.
-- Output: "▶ user text" / "◆ assistant text" / "◆ (thinking) ..." / "◆ [tool: read]"
-- Used by: ocs fish function (copy full transcript action)

SELECT CASE json_extract(m.data, '$.role')
       WHEN 'user' THEN '▶ '
       ELSE '◆ '
     END ||
     CASE json_extract(p.data, '$.type')
       WHEN 'text' THEN json_extract(p.data, '$.text')
       WHEN 'reasoning' THEN '(thinking) ' || COALESCE(json_extract(p.data, '$.text'), '')
       WHEN 'tool' THEN '[tool: ' || COALESCE(json_extract(p.data, '$.tool'), '?') || ']'
     END
FROM part p
JOIN message m ON p.message_id = m.id
WHERE p.session_id = ':sid'
  AND json_extract(p.data, '$.type') IN ('text', 'reasoning', 'tool')
ORDER BY p.time_created;
