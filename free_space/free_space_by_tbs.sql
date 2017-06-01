--- Free space by tablespace

set linesize 80
column tbs_name format a18

prompt --- --- --- --- dba_free_space --- --- --- ---
select *
from
(
select s.tbs_name,
       round(s.bytes / 1048576                    ) "Size Mb",
       round((s.bytes - nvl(f.bytes, 0)) / 1048576) "Used Mb",
       round(nvl(f.bytes, 0) / 1048576)             "Free Mb",
       round((1 - nvl(f.bytes, 0) / s.bytes) * 100) "% Used"
from (select df.tablespace_name tbs_name, sum(df.bytes) bytes
      from dba_data_files df
      group by df.tablespace_name) s,
     (select tablespace_name tbs_name, sum(bytes) bytes
      from dba_free_space
      group by tablespace_name) f
where s.tbs_name = f.tbs_name(+)
union all
select s.tbs_name,
       round(s.bytes / 1048576)                     "Size Mb",
       round(nvl(u.bytes, 0) / 1048576)             "Used Mb",
       round((s.bytes - nvl(u.bytes, 0)) / 1048576) "Free Mb",
       round((nvl(u.bytes, 0) / s.bytes) * 100)     "% Used"
from (select tf.tablespace_name tbs_name, sum(tf.bytes) bytes
      from dba_temp_files tf
      group by tf.tablespace_name) s,
     (select tablespace_name tbs_name, sum(bytes_used) bytes
      from v$temp_extent_pool
      group by tablespace_name) u
where s.tbs_name = u.tbs_name(+)
)
order by 5 desc
;

prompt --- --- --- --- dba_segments --- --- --- ---

select *
from
(
select s.tbs_name,
       round(s.bytes / 1048576)                     "Size Mb",
       round(nvl(u.bytes, 0) / 1048576)             "Used Mb",
       round((s.bytes - nvl(u.bytes, 0)) / 1048576) "Free Mb",
       round((nvl(u.bytes, 0) / s.bytes) * 100)     "% Used"
from (select df.tablespace_name tbs_name, sum(df.bytes) bytes
      from dba_data_files df
      group by df.tablespace_name) s,
     (select tablespace_name tbs_name, sum(bytes) bytes
      from dba_segments
      group by tablespace_name) u
where s.tbs_name = u.tbs_name(+)
union all
select s.tbs_name,
       round(s.bytes / 1048576)                     "Size Mb",
       round(nvl(u.bytes, 0) / 1048576)             "Used Mb",
       round((s.bytes - nvl(u.bytes, 0)) / 1048576) "Free Mb",
       round((nvl(u.bytes, 0) / s.bytes) * 100)     "% Used"
from (select tf.tablespace_name tbs_name, sum(tf.bytes) bytes
      from dba_temp_files tf
      group by tf.tablespace_name) s,
     (select tablespace_name tbs_name, sum(bytes_used) bytes
      from v$temp_extent_pool
      group by tablespace_name) u
where s.tbs_name = u.tbs_name(+)
)
order by 5 desc
;
