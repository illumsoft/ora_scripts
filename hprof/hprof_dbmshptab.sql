whenever sqlerror exit failure rollback;
whenever oserror  exit failure rollback;

alter session set current_schema = hprof;

/**
 * DBMS_HPROF
 * $ORACLE_HOME/rdbms/admin/dbmshptab.sql
 */

create table dbmshp_runs
(
  runid               number constraint dbmshp_runs_pk primary key, -- unique run identifier,
  run_timestamp       timestamp,
  total_elapsed_time  integer,
  run_comment         varchar2(2047) -- user provided comment for this run
);

comment on table dbmshp_runs is
  'Run-specific information for the hierarchical profiler';

create table dbmshp_function_info
(
  runid                  number constraint dbmshp_function_info_fk_runid references dbmshp_runs on delete cascade,
  symbolid               number,               -- unique internally generated
                                               -- symbol id for a run
  owner                  varchar2(32),         -- user who started run
  module                 varchar2(32),         -- module name
  type                   varchar2(32),         -- module type
  function               varchar2(4000),       -- function name
  line#                  number,               -- line number where function
                                               -- defined in the module.
  hash                   raw(32) default null, -- hash code of the method.
  -- name space/language info (such as PL/SQL, SQL)
  namespace              varchar2(32) default null,
  -- total elapsed time in this symbol (including descendats)
  subtree_elapsed_time   integer default null,
  -- self elapsed time in this symbol (not including descendants)
  function_elapsed_time  integer default NULL,
  -- number of total calls to this symbol
  calls                  integer default null,
  --
  constraint dbmshp_function_info_pk primary key (runid, symbolid)
);

comment on table dbmshp_function_info is
  'Information about each function in a run';

create table dbmshp_parent_child_info
(
  runid                  number,       -- unique (generated) run identifier
  parentsymid            number,       -- unique parent symbol id for a run
  childsymid             number,       -- unique child symbol id for a run
  -- total elapsed time in this symbol (including descendats)
  subtree_elapsed_time   integer DEFAULT NULL,
  -- self elapsed time in this symbol (not including descendants)
  function_elapsed_time  integer DEFAULT NULL,
  -- number of calls from the parent
  calls                  integer DEFAULT NULL,
  --
  constraint dbmshp_parent_child_info_fk_ch
    foreign key (runid, childsymid)
    references dbmshp_function_info(runid, symbolid) on delete cascade,
  constraint dbmshp_parent_child_info_fk_p
    foreign key (runid, parentsymid)
    references dbmshp_function_info(runid, symbolid) on delete cascade
);

comment on table dbmshp_parent_child_info is
  'Parent-child information from a profiler runs';

create sequence dbmshp_runnumber start with 1 nocache;

/**
 * Public synonyms and grants
 */
grant select                         on dbmshp_runnumber         to public;
grant select, insert, update, delete on dbmshp_runs              to public;
grant select, insert, update, delete on dbmshp_function_info     to public;
grant select, insert, update, delete on dbmshp_parent_child_info to public;

create public synonym dbmshp_runnumber         for dbmshp_runnumber;
create public synonym dbmshp_runs              for dbmshp_runs;
create public synonym dbmshp_function_info     for dbmshp_function_info;
create public synonym dbmshp_parent_child_info for dbmshp_parent_child_info;
