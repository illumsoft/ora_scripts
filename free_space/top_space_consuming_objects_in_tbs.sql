-- Top space-consuming object in the given tablespace

set linesize 80
set pagesize 50
column tbs_name format a8
column tb_sz_mb format 99999
column owner    format a10
column seg_name format a30
column seg_type format a8
column mbytes   format 99999

select * from (
  select s.tablespace_name tbs_name,
         (select sum(df.bytes) / 1048576
          from dba_data_files df
          where df.tablespace_name = s.tablespace_name
         ) tb_sz_mb,
         s.owner,
         s.segment_name seg_name,
         s.segment_type seg_type,
         s.bytes / 1048576 Mbytes
  from dba_segments s
  where s.tablespace_name = upper('&tablespace_name')
  order by Mbytes desc
)
where rownum <= &number_of_rows
;
