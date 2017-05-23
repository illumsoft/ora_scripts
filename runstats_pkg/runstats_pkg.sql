------------------------------------------------------------------------
-- as SYS
alter session set current_schema = hprof;

grant select on v$mystat to hprof;
grant select on v$statname to hprof;
grant select on v$latch to hprof;

------------------------------------------------------------------------
create view stats
as
  select 'STAT...' || a.name name, b.value
  from v$statname a, v$mystat b
  where a.statistic# = b.statistic#
  union all
  select 'LATCH..' || name, gets
  from v$latch
/

------------------------------------------------------------------------
create global temporary table run_stats
(
  runid varchar2(15),
  name  varchar2(80),
  value integer
)
on commit preserve rows
/
------------------------------------------------------------------------
create or replace package runstats_pkg
authid definer
as
  function print_sid_from_v$mystat return varchar2;
  procedure rs_start;
  procedure rs_middle;
  procedure rs_stop(p_difference_threshold in number default 0);
end runstats_pkg;
/
------------------------------------------------------------------------
create or replace package body runstats_pkg
as
  C_BEFORE constant varchar2(7) := 'before';
  C_RUN_1  constant varchar2(7) := 'after 1';
  C_RUN_2  constant varchar2(7) := 'after 2';

  g_start number;
  g_run1  number;
  g_run2  number;

  function print_sid_from_v$mystat return varchar2
  as
    v varchar2(100);
  begin
$if dbms_db_version.ver_le_10 $then
    select max(sid) into v from v$mystat;
$else
    select listagg(sid, ', ') within group (order by sid)
    into v
    from (select distinct sid from v$mystat);
$end
    return v;
  end print_sid_from_v$mystat;

  procedure rs_start
  as
  begin
    delete from run_stats;
    insert into run_stats select C_BEFORE, stats.* from stats;
    g_start := dbms_utility.get_time;
  end rs_start;

  procedure rs_middle
  as
  begin
    g_run1 := (dbms_utility.get_time - g_start);
    insert into run_stats select C_RUN_1, stats.* from stats;
    g_start := dbms_utility.get_time;
  end rs_middle;

  procedure rs_stop(p_difference_threshold in number default 0)
  as
    v_format varchar2(100);
  begin
    g_run2 := (dbms_utility.get_time - g_start);
    insert into run_stats select C_RUN_2, stats.* from stats;

    dbms_output.put_line('Run1 ran in ' || g_run1 || ' hsecs');
    dbms_output.put_line('Run2 ran in ' || g_run2 || ' hsecs');
    dbms_output.put_line('Run1 is ' || round(100 * g_run1 / nullif(g_run2, 0), 2) || '% of the Run2 time');
    dbms_output.new_line;

    dbms_output.put_line(rpad('Name', 40) || lpad('Run1', 14) || lpad('Run2', 14) || lpad('Diff', 10));

    select rpad('9', floor(log(10, max(value))) + 1, '9') into v_format from v$mystat;
    for x in (
$if dbms_db_version.ver_le_10 $then
      select rpad(a.name, 40)
             || to_char(b.value - a.value, v_format)
             || to_char(c.value - b.value, v_format)
             || to_char(((c.value - b.value) - (b.value - a.value)), v_format) diff
      from run_stats a, run_stats b, run_stats c
      where a.name = b.name
        and b.name = c.name
        and a.runid = C_BEFORE
        and b.runid = C_RUN_1
        and c.runid = C_RUN_2
        and (c.value - a.value) > 0
        and abs((c.value - b.value) - (b.value - a.value)) > p_difference_threshold
      order by abs((c.value - b.value) - (b.value - a.value))
$else
      select rpad(rs.name, 40)
             || to_char(rs.after_1 - rs.before, v_format)
             || to_char(rs.after_2 - rs.after_1, v_format)
             || to_char(((rs.after_2 - rs.after_1) - (rs.after_1 - rs.before)), v_format) diff
      from run_stats
      pivot (max(value) for runid in ('before' as before, 'after 1' as after_1, 'after 2' as after_2)) rs
      where (rs.after_2 - rs.before) > 0
        and abs((rs.after_2 - rs.after_1) - (rs.after_1 - rs.before)) > p_difference_threshold
      order by abs((rs.after_2 - rs.after_1) - (rs.after_1 - rs.before))
$end
    ) loop
      dbms_output.put_line(x.diff);
    end loop;
    dbms_output.new_line;

    dbms_output.put_line('Run1 latches total versus runs -- difference and pct');
    dbms_output.put_line(lpad('Run1', 11) || lpad('Run2', 11) || lpad('Diff', 11) || lpad('Pct', 8));
    for x in (
      select to_char(run1, v_format)
          || to_char(run2, v_format)
          || to_char(diff, v_format)
          || to_char(round(100 * run1 / run2, 2), '999.99') || '%' diff
$if dbms_db_version.ver_le_10 $then
      from (select sum(b.value - a.value) run1,
                   sum(c.value - b.value) run2,
                   sum((c.value - b.value) - (b.value - a.value)) diff
            from run_stats a, run_stats b, run_stats c
            where a.name = b.name
              and b.name = c.name
              and a.runid = C_BEFORE
              and b.runid = C_RUN_1
              and c.runid = C_RUN_2
              and a.name like 'LATCH%'
           )
$else
      from (select sum(rs.after_1 - rs.before) run1,
                   sum(rs.after_2 - rs.after_1) run2,
                   sum((rs.after_2 - rs.after_1) - (rs.after_1 - rs.before)) diff
            from run_stats
            pivot (max(value) for runid in ('before' as before, 'after 1' as after_1, 'after 2' as after_2)) rs
            where rs.name like 'LATCH%'
           )
$end
    ) loop
      dbms_output.put_line(x.diff);
    end loop;
  end rs_stop;
end runstats_pkg;
/
------------------------------------------------------------------------
grant execute on runstats_pkg to public;
------------------------------------------------------------------------
