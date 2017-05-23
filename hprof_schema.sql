/**
 * Create Objects in this Schema using
 * alter session set current_schema = hprof;
 */
create tablespace tools
  datafile '/path/to/dir/tools.dbf' size 16M
;

create user hprof identified by hprof
  temporary tablespace tmp
  default tablespace tools
  quota 12M on tools
  account lock
  password expire
;

