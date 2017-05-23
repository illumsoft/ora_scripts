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

  procedure clear_runs_stats;
  procedure run1_begin;
  procedure run1_end;
  procedure run1_show(p_value_threshold in number default 0);

  procedure run2_begin;
  procedure run2_end;
  procedure run2_show(p_value_threshold in number default 0);

  procedure show_diff(p_difference_threshold in number default 0);
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

  procedure clear_runs_stats
  as
  begin
    delete from run_stats;
  end clear_runs_stats;

  procedure run1_begin
  as
  begin
    -- delete from run_stats where substr(runid, 1, 5) = 'RUN1_';
    insert into run_stats select 'RUN1_BEGIN', stats.* from stats;
    g_start := dbms_utility.get_time;
  end run1_begin;

  procedure run1_end
  as
  begin
    g_run1 := (dbms_utility.get_time - g_start);
    insert into run_stats select 'RUN1_END', stats.* from stats;
  end run1_end;

  procedure run2_begin
  as
  begin
    -- delete from run_stats where substr(runid, 1, 5) = 'RUN2_';
    insert into run_stats select 'RUN2_BEGIN', stats.* from stats;
    g_start := dbms_utility.get_time;
  end run2_begin;

  procedure run2_end
  as
  begin
    g_run2 := (dbms_utility.get_time - g_start);
    insert into run_stats select 'RUN2_END', stats.* from stats;
  end run2_end;

  procedure show_diff(p_difference_threshold in number default 0)
  as
    v_name_len  constant pls_integer := 40;
    v_value_len          pls_integer;
    v_format             varchar2(40);
  begin
    -- Prepare formats
    select max(length(to_char(abs(value)))) into v_value_len from run_stats;
    v_format := rpad('9', v_value_len, '9');

    -- Output values
    dbms_output.put_line('Run1 ran in ' || g_run1 || ' hsecs');
    dbms_output.put_line('Run2 ran in ' || g_run2 || ' hsecs');
    dbms_output.put_line('Run1 is ' || round(100 * g_run1 / nullif(g_run2, 0), 2) || '% of the Run2 time');
    dbms_output.new_line;
    dbms_output.put_line(
         rpad('Name', v_name_len)
      || lpad('Run1', v_value_len + 1)
      || lpad('Run2', v_value_len + 1)
      || lpad('Diff', v_value_len + 1) || ' (Run2 - Run1)');

    for x in (
      select rpad(rs.name, v_name_len)
          || to_char(rs.run1_end - rs.run1_begin, v_format)
          || to_char(rs.run2_end - rs.run2_begin, v_format)
          || to_char(((rs.run2_end - rs.run2_begin) - (rs.run1_end - rs.run1_begin)), v_format) diff
      from run_stats
      pivot (
        max(value) for runid in (
          'RUN1_BEGIN' as run1_begin, 'RUN1_END' as run1_end,
          'RUN2_BEGIN' as run2_begin, 'RUN2_END' as run2_end)
      ) rs
      where abs((rs.run2_end - rs.run2_begin) - (rs.run1_end - rs.run1_begin)) > p_difference_threshold
      order by substr(rs.name, 1, 4), abs((rs.run2_end - rs.run2_begin) - (rs.run1_end - rs.run1_begin))
    )
    loop dbms_output.put_line(x.diff); end loop;
    dbms_output.new_line;

    dbms_output.put_line('Total Run1 latches versus Run2 - difference and percent');
    dbms_output.put_line(
         lpad('Run1', v_value_len + 1)
      || lpad('Run2', v_value_len + 1)
      || lpad('Diff', v_value_len + 1)
      || lpad('Pct', 8));

    for x in (
      select to_char(run1, v_format)
          || to_char(run2, v_format)
          || to_char(diff, v_format)
          || to_char(round(100 * run1 / run2, 2), '999.99') || '%' diff
      from (select sum(rs.run1_end - rs.run1_begin) run1,
                   sum(rs.run2_end - rs.run1_begin) run2,
                   sum((rs.run2_end - rs.run2_begin) - (rs.run1_end - rs.run1_begin)) diff
            from run_stats
            pivot (
              max(value) for runid in (
                'RUN1_BEGIN' as run1_begin, 'RUN1_END' as run1_end,
                'RUN2_BEGIN' as run2_begin, 'RUN2_END' as run2_end
              )
            ) rs
            where rs.name like 'LATCH%'
           )
    )
    loop dbms_output.put_line(x.diff); end loop;

  end show_diff;

  procedure run1_show(p_value_threshold in number default 0)
  as
    v_name_len  constant pls_integer := 40;
    v_value_len          pls_integer;
    v_format             varchar2(40);
  begin
    -- Prepare formats
    select max(length(to_char(abs(value)))) into v_value_len from run_stats;
    v_format := rpad('9', v_value_len, '9');

    -- Output values
    dbms_output.put_line('Run1 ran in ' || g_run1 || ' hsecs');
    dbms_output.new_line;
    dbms_output.put_line(rpad('Name', v_name_len) || lpad('Run1', v_value_len + 1));
    for x in (
      select rpad(rs.name, v_name_len) || to_char(rs.run1_end - rs.run1_begin, v_format) diff
      from run_stats
      pivot (max(value) for runid in ('RUN1_BEGIN' as run1_begin, 'RUN1_END' as run1_end)) rs
      where abs(rs.run1_end - rs.run1_begin) > p_value_threshold
      order by substr(rs.name, 1, 4), abs((rs.run1_end - rs.run1_begin))
    )
    loop dbms_output.put_line(x.diff); end loop;

    dbms_output.new_line;
    dbms_output.put('Total Run1 latches: ');
    for x in (
      select to_char(run1, v_format) diff
      from (
        select sum(rs.run1_end - rs.run1_begin) run1
        from run_stats
        pivot (max(value) for runid in ( 'RUN1_BEGIN' as run1_begin, 'RUN1_END' as run1_end)) rs
        where rs.name like 'LATCH%'
      )
    )
    loop dbms_output.put_line(x.diff); end loop;

  end run1_show;

  procedure run2_show(p_value_threshold in number default 0)
  as
    v_name_len  constant pls_integer := 40;
    v_value_len          pls_integer;
    v_format             varchar2(40);
  begin
    -- Prepare formats
    select max(length(to_char(abs(value)))) into v_value_len from run_stats;
    v_format := rpad('9', v_value_len, '9');

    -- Output values
    dbms_output.put_line('Run2 ran in ' || g_run2 || ' hsecs');
    dbms_output.new_line;
    dbms_output.put_line(rpad('Name', v_name_len) || lpad('Run2', v_value_len + 1));
    for x in (
      select rpad(rs.name, v_name_len) || to_char(rs.run2_end - rs.run2_begin, v_format) diff
      from run_stats
      pivot (max(value) for runid in ('RUN2_BEGIN' as run2_begin, 'RUN2_END' as run2_end)) rs
      where abs(rs.run2_end - rs.run2_begin) > p_value_threshold
      order by substr(rs.name, 1, 4), abs((rs.run2_end - rs.run2_begin))
    )
    loop dbms_output.put_line(x.diff); end loop;

    dbms_output.new_line;
    dbms_output.put('Total Run2 latches: ');
    for x in (
      select to_char(run2, v_format) diff
      from (
        select sum(rs.run2_end - rs.run2_begin) run2
        from run_stats
        pivot (max(value) for runid in ( 'RUN2_BEGIN' as run2_begin, 'RUN2_END' as run2_end)) rs
        where rs.name like 'LATCH%'
      )
    )
    loop dbms_output.put_line(x.diff); end loop;

  end run2_show;

end runstats_pkg;
/
------------------------------------------------------------------------
grant execute on runstats_pkg to public;
------------------------------------------------------------------------
