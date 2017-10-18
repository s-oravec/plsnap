define l_schema_name = &1

set feedback on

prompt .. Granting privileges to package &&g_package_name in schema &&l_schema_name

prompt .. Granting session to &&l_schema_name
grant create session to &&l_schema_name;

prompt .. Granting table to &&l_schema_name
grant create table to &&l_schema_name;

prompt .. Granting procedure to &&l_schema_name
grant create procedure to &&l_schema_name;

 prompt .. Granting privs required to scrape DDL
grant select_catalog_role to &&l_schema_name;

prompt Grant execute on all DBMS%, OWA%, UTL%, APEX%, CTX%, DEBUG%, ORD%, SDO%, SEM% packages with grant option
begin
    for cmd in (select 'grant execute on ' || owner || '.' || object_name || ' to &&l_schema_name with grant option' as text
                  from dba_objects
                 where owner = 'SYS'
                   and object_type = 'PACKAGE'
                   and object_name not like '%$%'
                   and ((regexp_substr(object_name, '[^_]+', 1, 1) in ('DBMS', 'OWA', 'UTL', 'APEX', 'CTX', 'DEBUG', 'ORD', 'SDO', 'SEM'))
                       or object_name in ('HTP', 'HTF'))
               ) loop
        begin
            execute immediate cmd.text;
        exception
            when others then
                dbms_output.put_line('ERROR> During ' || cmd.text || chr(10) || 'ERROR> ' || sqlerrm);
        end;
    end loop;
end;
/

prompt Grant select on V$ views with grant option
begin
    for cmd in (select 'grant select on ' || owner || '.' || object_name || ' to &&l_schema_name with grant option' as text
                  from dba_objects
                 where owner = 'SYS'
                   and object_type = 'VIEW'
                   and object_name like 'V\_$%' escape '\') loop
        begin
            execute immediate cmd.text;
        exception
            when others then
                dbms_output.put_line('ERROR> During ' || cmd.text || chr(10) || 'ERROR> ' || sqlerrm);
        end;
    end loop;
end;
/

prompt Grant select on DBA views with grant option
begin
    for cmd in (select 'grant select on ' || owner || '.' || object_name || ' to &&l_schema_name with grant option' as text
                  from dba_objects
                 where owner = 'SYS'
                   and object_type = 'VIEW'
                   and object_name like 'DBA_%') loop
        begin
            execute immediate cmd.text;
        exception
            when others then
                dbms_output.put_line('ERROR> During ' || cmd.text || chr(10) || 'ERROR> ' || sqlerrm);
        end;
    end loop;
end;
/

prompt .. Granting select/execute/drop any object
grant grant  any privilege to &&l_schema_name;
grant grant  any role to &&l_schema_name;
grant grant  any object privilege to &&l_schema_name;
grant create any procedure to &&l_schema_name;
grant drop   any procedure to &&l_schema_name;
grant create any index to &&l_schema_name;
grant drop   any index to &&l_schema_name;
grant alter  any index to &&l_schema_name;
grant create any procedure to &&l_schema_name;
grant drop   any procedure to &&l_schema_name;
grant create any type to &&l_schema_name;
grant drop   any type to &&l_schema_name;
grant create any table to &&l_schema_name;
grant drop   any table to &&l_schema_name;
grant alter  any table to &&l_schema_name;
grant select any table to &&l_schema_name;
grant insert any table to &&l_schema_name;
grant create any view to &&l_schema_name;
grant drop   any view to &&l_schema_name;
grant create any trigger to &&l_schema_name;
grant drop   any trigger to &&l_schema_name;
grant alter  any trigger to &&l_schema_name;
grant create any synonym to &&l_schema_name;
grant drop   any synonym to &&l_schema_name;
grant create any sequence to &&l_schema_name;
grant drop   any sequence to &&l_schema_name;
grant select any sequence to &&l_schema_name;
grant create any directory to &&l_schema_name;
grant drop   any directory to &&l_schema_name;
grant create any cluster to &&l_schema_name;
grant drop   any cluster to &&l_schema_name;
grant alter  any cluster to &&l_schema_name;
grant create any context to &&l_schema_name;
grant drop   any context to &&l_schema_name;
grant create any edition to &&l_schema_name;
grant drop   any edition to &&l_schema_name;
grant create any dimension to &&l_schema_name;
grant drop   any dimension to &&l_schema_name;
grant create any indextype to &&l_schema_name;
grant drop   any indextype to &&l_schema_name;
grant create any job to &&l_schema_name;
grant drop   any job to &&l_schema_name;
grant create any library to &&l_schema_name;
grant drop   any library to &&l_schema_name;
grant create any materialized view to &&l_schema_name;
grant drop   any materialized view to &&l_schema_name;

grant create session        to &&l_schema_name;
grant debug connect session to &&l_schema_name;

undefine l_schema_name
