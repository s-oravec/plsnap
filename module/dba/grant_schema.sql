define l_schema_name = &1

set feedback on

prompt .. Granting privileges to package &&g_package_name in schema &&l_schema_name

prompt .. Granting session to &&l_schema_name
grant create session to &&l_schema_name;

prompt .. Granting table to &&l_schema_name
grant create table to &&l_schema_name;

prompt .. Granting procedure to &&l_schema_name
grant create procedure to &&l_schema_name;

prompt .. Granting synonym to &&l_schema_name
grant create synonym to &&l_schema_name;

prompt .. Granting privs required to scrape DDL
grant select_catalog_role to &&l_schema_name;
prompt .. Granting select on DBA views
grant select on dba_sys_privs to &&l_schema_name;
grant select on dba_tab_privs to &&l_schema_name;
grant select on dba_col_privs to &&l_schema_name;
grant select on dba_objects to &&l_schema_name;
grant select on dba_dependencies to &&l_schema_name;
grant select on dba_indexes to &&l_schema_name;
grant select on dba_constraints to &&l_schema_name;
grant select on dba_errors to &&l_schema_name;

prompt .. Granting select/execute/drop any object
grant grant   any privilege to &&l_schema_name;
grant grant   any role to &&l_schema_name;
grant grant   any object privilege to &&l_schema_name;
grant create  any procedure to &&l_schema_name;
grant drop    any procedure to &&l_schema_name;
grant create  any index to &&l_schema_name;
grant drop    any index to &&l_schema_name;
grant alter   any index to &&l_schema_name;
grant create  any procedure to &&l_schema_name;
grant drop    any procedure to &&l_schema_name;
grant create  any type to &&l_schema_name;
grant drop    any type to &&l_schema_name;
grant create  any table to &&l_schema_name;
grant drop    any table to &&l_schema_name;
grant alter   any table to &&l_schema_name;
grant select  any table to &&l_schema_name;
grant insert  any table to &&l_schema_name;
grant create  any view to &&l_schema_name;
grant drop    any view to &&l_schema_name;
grant create  any trigger to &&l_schema_name;
grant drop    any trigger to &&l_schema_name;
grant alter   any trigger to &&l_schema_name;
grant create  any synonym to &&l_schema_name;
grant drop    any synonym to &&l_schema_name;
grant create  any sequence to &&l_schema_name;
grant drop    any sequence to &&l_schema_name;
grant select  any sequence to &&l_schema_name;

grant create session        to &&l_schema_name;
grant debug connect session to &&l_schema_name;

undefine l_schema_name
