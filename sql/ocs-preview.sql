-- ocs-preview.sql
-- Clean transcript preview for a single session (text parts only).
-- :sid is replaced by sed before sqlite3 runs.
-- Output: "▶ user text" / "◆ assistant text" lines, chronological.
-- Used by: ocs fish function (fzf --preview)

SELECT CASE json_extract(m.data, '$.role')
       WHEN 'user' THEN '▶ '
       ELSE '◆ '
     END || json_extract(p.data, '$.text')
FROM part p
JOIN message m ON p.message_id = m.id
WHERE p.session_id = ':sid'
  AND json_extract(p.data, '$.type') = 'text'
  AND json_extract(p.data, '$.text') IS NOT NULL
  AND json_extract(p.data, '$.text') != ''
ORDER BY p.time_created;
