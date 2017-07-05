select s.sid, s.serial#, s.username, s.command, s.machine, s.program, s.module, s.action, s.osuser,
       round(p.pga_used_mem / 1048576) as "PGA Used Mb", round(p.pga_max_mem / 1048576) as "PGA Max Mb",
       s.wait_class, s.status, s.state, s.event,
       s.row_wait_obj#,
       decode(s.wait_class, 'Idle', null, o.object_type) object_type,
       decode(s.wait_class, 'Idle', null, o.object_name) object_name,
       s.p1text, s.p1,
       s.blocking_session, s.blocking_session_status,
       s.seconds_in_wait, s.wait_time_micro,
       s.sql_id, sq.sql_text,
       (select trunc(sum(seq.bytes) / 1024576) from dba_segments seq, v$rollname rn, v$transaction t
        where t.ses_addr = s.saddr and rn.name = seq.segment_name and rn.usn = t.xidusn
       ) undo_size_mb,
       to_char(s.sql_exec_start, 'YYYY-MM-DD HH24:MI:SS') sql_exec_start,
       replace(sq.last_load_time, '/', ' ') last_load_time,
       to_char(sq.last_active_time, 'YYYY-MM-DD HH24:MI:SS') last_active_time,
       sq.cpu_time,
       sq.elapsed_time,
       sq.sharable_mem,
       sq.persistent_mem,
       sq.runtime_mem,
       sq.sorts,
       sq.fetches,
       sq.executions,
       sq.end_of_fetch_count,
       sq.users_executing,
       sq.parse_calls,
       sq.disk_reads,
       sq.direct_writes,
       sq.buffer_gets,
       sq.application_wait_time app_wait_micro,
       sq.concurrency_wait_time conc_wait_micro,
       sq.user_io_wait_time user_io_wait_micro,
       sq.plsql_exec_time plsql_exec_micro,
       sq.java_exec_time java_exec_micro,
       sq.rows_processed,
       sq.command_type,
       sq.child_number,
       sq.object_status,
       --sq.program_id,
       --sq.program_line#,
       --sq.physical_read_requests,
       sq.physical_read_bytes,
       --sq.physical_write_requests,
       sq.physical_write_bytes,
       --sq.optimized_phy_read_requests,
       case when sq.sql_id is not null then dbms_sqltune.report_sql_monitor(sql_id => sq.sql_id, sql_plan_hash_value => sq.plan_hash_value, type => 'HTML') end sql_plan
       --case when sq.sql_id is not null then dbms_xplan.display_awr(sql_id => sq.sql_id, plan_hash_value => sq.plan_hash_value) end sql_plan_collection
from v$session s, v$process p, v$sql sq, dba_objects o
where s.paddr = p.addr
  and s.sql_address = sq.address(+)
  and s.sql_hash_value = sq.hash_value(+)
  and s.row_wait_obj# = o.object_id(+)
  and p.background is null
;
