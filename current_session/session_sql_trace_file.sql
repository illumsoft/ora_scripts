
-- Current blockers
select * from v$session_blockers;
-- Current transaction
select * from v$transaction;

-- Current locks owned by transaction state objects
select * from v$transaction_enqueue;

-- tracefile
select s.sid, s.serial#, s.sql_id,
       s.username,
       s.status, s.osuser, s.machine, s.program, s.module,
       s.blocking_session, s.blocking_session_status,
       s.final_blocking_session, s.final_blocking_session_status,
       s.sql_trace, s.sql_trace_waits, s.sql_trace_binds, s.sql_trace_plan_stats,
       p.tracefile
from v$session s
join v$process p on (p.addr = s.paddr)
where p.background is null -- except system background processes
;

-- blocking session
select s.sid, s.serial#, s.username, s.status, s.osuser,
       -- s.machine, s.program, s.module,
       s.blocking_session, s.blocking_session_status,
       s.final_blocking_session, s.final_blocking_session_status
from v$session s
join v$process p on (p.addr = s.paddr)
where p.background is null -- except system background processes
;

-- SQL run by session
select ses.sid, ses.serial#, ses.username,
       ses.sql_id, sq.sql_text,
       sq.sharable_mem, sq.persistent_mem, sq.runtime_mem, sq.sorts,
       sq.parse_calls, sq.disk_reads, sq.direct_writes, sq.buffer_gets, sq.rows_processed,
       sq.cpu_time, sq.elapsed_time, sq.last_load_time,
       ses.status, ses.osuser, ses.machine, ses.program, ses.module
from v$session ses
join v$process p on (p.addr = ses.paddr)
left outer join v$sql sq on (
           sq.address = ses.sql_address
       and sq.hash_value = ses.sql_hash_value
       and sq.child_number = ses.sql_child_number
     )
where p.background is null -- except system background processes
  and ses.sql_id is not null
;

-- UNDO space usage
select s.sid, s.serial#,
       t.xidusn, t.xidslot, t.xidsqn,
       t.start_date, t.used_ublk,
       s.sid, s.serial#, s.sql_id,
       (select trunc(sum(seq.bytes) / 1024576)
        from dba_segments seq
        join v$rollname rn on (rn.name = seq.segment_name)
        where rn.usn = t.xidusn
       ) seg_size_mb,
       (select sql_fulltext from v$sql st
        where st.address = s.sql_address
          and st.hash_value = s.sql_hash_value
          and st.child_number = s.sql_child_number
       ) sql_text,
       s.username,
       s.status, s.osuser, s.machine, s.program, s.module
from v$transaction t
left outer join v$session s on (s.saddr = t.ses_addr)
;
select * from dba_segments seg where seg.segment_type = 'UNDO';
select * from v$undostat;


-- temp space usage
select s.sid, s.serial#, s.sql_id,
       (select sql_fulltext from v$sql st
        where st.address = s.sql_address
          and st.hash_value = s.sql_hash_value
          and st.child_number = s.sql_child_number
       ) sql_text,
       s.username,
       s.status, s.osuser, s.machine, s.program, s.module
from v$session s
join v$process p on (p.addr = s.paddr)
where p.background is null -- except system background processes
;

-- template

select ses.sid, ses.serial#, ses.sql_id sess_sql_id,
       s.sql_fulltext, s.sorts,
       ses.username,
       ses.status, ses.osuser, ses.machine, ses.program, ses.module
from v$session ses
join v$process p on (p.addr = ses.paddr)
left outer join v$sql s
  on (s.address = ses.sql_address and s.hash_value = ses.sql_hash_value and s.child_number = ses.sql_child_number)
where p.background is null -- except system background processes
;
