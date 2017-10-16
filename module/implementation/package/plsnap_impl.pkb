create or replace package body plsnap_impl as

    gc_PARTTYPE_INDEXES    constant varchar2(7) := 'INDEXES';
    gc_PARTTYPE_PRIVILEGES constant varchar2(10) := 'PRIVILEGES';
    gc_PARTTYPE_DATA       constant varchar2(4) := 'DATA';
    gc_PARTTYPE_MAIN       constant varchar2(4) := 'MAIN';
    gc_PARTTYPE_ALTER      constant varchar2(5) := 'ALTER';

    subtype typ_ObjectRecord is dba_objects%rowtype;
    type typ_MetadataTab is table of plsnap_Metadata%rowtype;

    e_fkrely_on_pknorely exception;
    pragma exception_init(e_fkrely_on_pknorely, -25158);
    e_name_already_used exception;
    pragma exception_init(e_name_already_used, -955);
    e_success_with_comp_error exception;
    pragma exception_init(e_success_with_comp_error, -24344);
    e_partition_does_not_exist exception;
    pragma exception_init(e_partition_does_not_exist, -2149);
    gc_MAX_ITERATIONS constant pls_integer := 20;


    ----------------------------------------------------------------------------  
    function getDataTableName(a_idMetadata in plsnap_Metadata.idMetadata%type) return varchar2 is
    begin
        return 'PLSNAP_' || a_idMetadata;
    end;

    ----------------------------------------------------------------------------
    procedure reraise(a_message in varchar2 default null) is
    begin
        if a_message is not null then
            raise_application_error(-20000, a_message || ' ' || sqlerrm, false);
        else
            raise_application_error(-20000, sqlerrm, false);
        end if;
    end;

    ----------------------------------------------------------------------------
    function isToplevelObject(a_object in typ_ObjectRecord) return BOOLEAN is
    begin
        -- NoFormat Start
        return a_object.object_type not like '%PARTITION'
           and a_object.object_type not IN('LOB', 'DATABASE LINK')
           and a_object.object_name not like 'BIN$%'
           and a_object.generated != 'Y' -- no IOTs and stuff
        ;
        -- NoFormat End
    end;

    ----------------------------------------------------------------------------
    function get_sequenceDdl
    (
        a_schemaName in plsnap_Metadata.schemaName%type,
        a_objectName in plsnap_Metadata.objectName%type
    ) return clob is
        l_clob      clob;
        l_startWith integer;
    begin
        -- get ddl - in which START with is "rounded" to multiple of sequence CACHE
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', false);
        l_clob := dbms_metadata.get_ddl('SEQUENCE', a_objectName, a_schemaName);
        -- and fix it - change it to START with nextVal
        execute immediate 'select ' || a_schemaName || '.' || a_objectName || '.nextval from dual'
            into l_startWith;
        -- replace START with
        return regexp_replace(l_clob, 'START with -?[0-9]+', 'START with ' || l_startWith);
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.get_sequenceDdl');
    end;

    ----------------------------------------------------------------------------
    function get_ddl
    (
        a_schemaName in plsnap_Metadata.schemaName%type,
        a_objectName in plsnap_Metadata.objectName%type,
        a_objectType in plsnap_Metadata.objectType%type
    ) return clob is
    begin
        case
            when a_objectType in ('VIEW', 'SYNONYM', 'PROCEDURE', 'FUNCTION') then
                dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', false);
                return dbms_metadata.get_ddl(a_objectType, a_objectName, a_schemaName);
            when a_objectType = 'TABLE' then
                dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);
                return dbms_metadata.get_ddl(a_objectType, a_objectName, a_schemaName);
            when a_objectType = 'INDEX' then
                dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);
                return dbms_metadata.get_ddl(a_objectType, a_objectName, a_schemaName);
            when a_objectType = 'SEQUENCE' then
                return get_sequenceDdl(a_schemaName, a_objectName);
            when a_objectType = 'TRIGGER' then
                dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', false);
                return dbms_metadata.get_ddl(a_objectType, a_objectName, a_schemaName);
            when a_objectType in ('PACKAGE', 'TYPE') then
                dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', false);
                dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SPECIFICATION', true);
                dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'BODY', false);
                return dbms_metadata.get_ddl(a_objectType, a_objectName, a_schemaName);
            when a_objectType in ('PACKAGE BODY', 'TYPE BODY') then
                dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', false);
                dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SPECIFICATION', false);
                dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'BODY', true);
                return dbms_metadata.get_ddl(regexp_substr(a_objectType, '[^ ]+', 1, 1), a_objectName, a_schemaName);
            else
                raise_application_error(-20000, a_objectType || ' is not supported, yet');
        end case;
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.get_ddl');
    end;

    ----------------------------------------------------------------------------
    procedure populateSystemPrivileges
    (
        a_idSnapshot in plsnap_Snapshot.idSnapshot%type,
        a_schemaName in plsnap_Schema.name%type
    ) is
    begin
        insert 
          into plsnap_Metadata (idSnapshot, schemaName, ObjectName, ObjectType, ObjectStatus, part, partType, ddl)
        select a_idSnapshot,
               a_schemaName,
               privilege,
               'SYS_PRIV',
               'VALID',
               1,
               gc_PARTTYPE_MAIN,
               'GRANT ' || privilege || ' TO ' || grantee || case admin_option when 'YES' then ' with ADMIN OPTION ' else '' end
          from dba_sys_privs 
         where grantee = a_schemaName 
         order by privilege
        ;
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.populateSystemPrivileges');
    end;

    ----------------------------------------------------------------------------
    procedure populateTablePrivileges
    (
        a_idSnapshot in plsnap_Snapshot.idSnapshot%type,
        a_schemaName in plsnap_Schema.name%type
    ) is
    begin
        insert 
          into plsnap_Metadata (idSnapshot, schemaName, ObjectName, ObjectType, ObjectStatus, part, partType, ddl)
        with tabPrivs as (
            select grantee,
                   owner,
                   table_name,
                   type,
                   grantable,
                   hierarchy,
                   listagg(privilege, ',') within group(order by privilege) as privilege
                   -- can be granted by more users, we need only one
              from (select distinct grantee, owner, table_name, privilege, grantable, hierarchy, type from dba_tab_privs)
             where grantee = a_schemaName
               and table_name not like 'BIN$%'
             group by grantee, owner, table_name, type, grantable, hierarchy
             order by owner, type, table_name, privilege            
        )
        select a_idSnapshot,
               a_schemaName,
               type || ':' || owner || ':' || table_name || ':grantable=' || grantable || ':hierarchy=' || hierarchy,
               'TAB_PRIV',
               'VALID',
               1,
               gc_PARTTYPE_MAIN,
               'GRANT '
               || privilege || ' on '
               || case type when 'DIRECTORY' then ' DIRECTORY ' end
               || owner || '.' || table_name
               || ' TO ' || grantee
               || case grantable when 'YES' then ' with GRANT OPTION ' end
               || case hierarchy when 'YES' then ' with HIERARCHY OPTION ' end
          from tabPrivs
        ;
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.populateTablePrivileges');
    end;

    ----------------------------------------------------------------------------
    procedure populateColumnPrivileges
    (
        a_idSnapshot in plsnap_Snapshot.idSnapshot%type,
        a_schemaName in plsnap_Schema.name%type
    ) is
    begin
        insert
          into plsnap_Metadata
            (idSnapshot, schemaName, ObjectName, ObjectType, ObjectStatus, part, partType, ddl)
        with colPrivs as (
            select priv.grantee,
                   priv.owner,
                   priv.table_name,
                   obj.object_type as type,
                   priv.column_name,
                   priv.grantable,
                   listagg(priv.privilege, ',') within group(order by priv.privilege) as privilege
              from dba_col_privs priv
             inner join dba_objects obj on (obj.owner = priv.owner and obj.object_name = priv.TABLE_NAME)
             where priv.grantee = a_schemaName
               and priv.table_name not like 'BIN$%'
             group by priv.grantee, priv.owner, priv.table_name, obj.object_type, priv.column_name, priv.Grantable
             order by priv.owner, obj.object_Type, priv.table_name, priv.column_name
        )
        select a_idSnapshot,
               a_schemaName,
               type || ':' || owner || ':' || table_name || ':' || column_name || ':grantable=' || grantable,
               'COL_PRIV',
               'VALID',
               1,
               gc_PARTTYPE_MAIN,
               'GRANT ' || privilege || '(' || column_name || ') on ' || owner || '.' ||
               table_name || ' TO ' || grantee || case grantable when 'YES' then
               ' with GRANT OPTION ' else '' end
          from colPrivs
        ;
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.populateColumnPrivileges');
    end;


    ----------------------------------------------------------------------------
    procedure logForObject
    (
        a_comments   in varchar2,
        a_schemaName in varchar2,
        a_objectName in varchar2,
        a_objectType in varchar2,
        a_idMetadata in integer default null,
        a_logLevel   in varchar2
    ) is
    begin
        if a_idMetadata is null then
            dbms_output.put_line(a_logLevel || '> ' || a_comments || ' object=' || a_objectType || ':' || a_schemaName || '.' ||
                                 a_objectName);
        else
            dbms_output.put_line(a_logLevel || '> ' || a_comments || ' idMetadata=' || a_idMetadata || ',object=' || a_objectType || ':' ||
                                 a_schemaName || '.' || a_objectName);
        end if;
        if sqlerrm is not null then
            -- sqlerrm
            dbms_output.put_line(a_logLevel || '> ' || sqlerrm || chr(10) ||
                                 '----------------------------------------------------------------------------' || chr(10) ||
                                 'Error stack:' || chr(10) || dbms_utility.format_error_stack || dbms_utility.format_error_backtrace);
        end if;
        -- dba_errors
        for err in (select rpad(err.line, MAX(length(err.line)) over(), ' ') || ' ' || err.text as text
                      from dba_errors err
                     where err.owner = a_schemaName
                       and err.name = a_objectName
                     order by Line) loop
            dbms_output.put_line('DETAIL> ' || err.text);
        end loop;
    end;


    ----------------------------------------------------------------------------
    procedure logErrorForObject
    (
        a_comments   in varchar2,
        a_schemaName in varchar2,
        a_objectName in varchar2,
        a_objectType in varchar2,
        a_idMetadata in integer default null
    ) is
    begin
        logForObject(a_comments, a_schemaName, a_objectName, a_objectType, a_idMetadata, 'ERROR');
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.logErrorForObject');
    end;
    
    ----------------------------------------------------------------------------
    procedure logErrorForObject
    (
        a_comments in varchar2,
        a_metadata in plsnap_Metadata%rowtype
    ) is
    begin
        logForObject(a_comments, a_metadata.schemaName, a_metadata.objectName, a_metadata.objectType, a_metadata.idMetadata, 'ERROR');
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.logWarningForObject');
    end;
    

    ----------------------------------------------------------------------------
    procedure logWarningForObject
    (
        a_comments   in varchar2,
        a_schemaName in varchar2,
        a_objectName in varchar2,
        a_objectType in varchar2,
        a_idMetadata in integer default null
    ) is
    begin
        logForObject(a_comments, a_schemaName, a_objectName, a_objectType, a_idMetadata, 'WARNING');
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.logWarningForObject');
    end;

    ----------------------------------------------------------------------------
    procedure logWarningForObject
    (
        a_comments in varchar2,
        a_metadata in plsnap_Metadata%rowtype
    ) is
    begin
        logForObject(a_comments, a_metadata.schemaName, a_metadata.objectName, a_metadata.objectType, a_metadata.idMetadata, 'WARNING');
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.logWarningForObject');
    end;

    ----------------------------------------------------------------------------
    -- Refactored procedure populateObjectsMetadata
    procedure populateObjectsMetadata
    (
        a_idSnapshot in plsnap_Snapshot.idSnapshot%type,
        a_schemaName in plsnap_Schema.name%type
    ) is
    begin
        for l_object in (
                         -- filter out indexes used in constraints with different name - these indexes are created in that constraint
                         -- TODO: can you have procedure or other object with same name as index? - if yes, then rewrite this
                         select obj.*
                           from dba_objects obj
                           left outer join dba_constraints cstr
                                        on (cstr.owner = obj.owner
                                            and cstr.index_name = obj.object_name)
                          where obj.owner = a_schemaName
                            and (cstr.constraint_name is null
                                 or cstr.constraint_name is not null and obj.object_name = cstr.constraint_name)
                          order by object_name
                         --
                         ) loop
            if isToplevelObject(l_object) then
                declare
                    l_ddl             plsnap_Metadata.ddl%type;
                    l_ddlPart         plsnap_Metadata.ddl%type;
                    l_partType        plsnap_Metadata.partType%type;
                    l_partName        plsnap_Metadata.partName%type;
                    l_idMetadataDummy plsnap_Metadata.idMetadata%type;

                    function storeMetadata
                    (
                        p_ddl  in clob,
                        p_part in pls_integer
                    ) return plsnap_Metadata.idMetadata%type is
                        l_Result plsnap_Metadata.idMetadata%type;
                    begin
                        -- store metadata
                        insert into plsnap_Metadata
                            (idSnapshot, schemaName, ObjectName, ObjectType, ObjectStatus, part, partType, partName, ddl)
                        values
                            (a_idSnapshot,
                             l_object.owner,
                             l_object.object_name,
                             l_object.object_type,
                             l_object.status,
                             p_part,
                             l_partType,
                             l_partName,
                             p_ddl)
                        returning idMetadata into l_Result;
                        --
                        return l_Result;
                        --
                    end;
                    --
                begin
                    --
                    l_partType := gc_PARTTYPE_MAIN;
                    -- TODO: refactor - split into more methods
                    if l_object.object_type in ('TABLE', 'INDEX') then
                        l_ddl := get_ddl(a_schemaName, l_object.object_name, l_object.object_type);
                        -- split at terminator in more parts
                        for l_part in 1 .. regexp_count(l_ddl, ';') loop
                            -- extract part
                            l_ddlPart := regexp_substr(l_ddl, '[^;]+', 1, l_part);
                            --
                            if l_part != 1 and l_object.object_type = 'TABLE' then
                                -- NoFormat Start
                                l_partName := cast(regexp_substr(l_ddlPart, 'ALTER TABLE (".*?"\.".*?") ADD CONSTRAINT "(.*?)"', 1, 1, null, 2) as varchar2);
                                -- NoFormat End
                                if l_ddlPart like '%FOREIGN KEY%' then
                                    l_partType := 'FOREIGN KEY';
                                elsif l_ddlPart like '%PRIMARY KEY%' then
                                    l_partType := 'PRIMARY KEY';
                                elsif l_ddlPart like '% UNIQUE %' then
                                    l_partType := 'UNIQUE';
                                elsif l_ddlPart like '% CHECK %' then
                                    l_partType := 'CHECK';
                                end if;
                            end if;
                            -- store metadata
                            l_idMetadataDummy := storeMetadata(l_ddlPart, l_part);
                            --
                            if l_part = 1 and l_object.object_type = 'TABLE' then
                                l_ddlPart := null;
                                -- create virtual parts
                                -- data
                                l_partName        := null;
                                l_partType        := gc_PARTTYPE_DATA;
                                l_idMetadataDummy := storeMetadata(null, -1);
                                -- indexes
                                l_partType        := gc_PARTTYPE_INDEXES;
                                l_idMetadataDummy := storeMetadata(null, -2);
                            end if;
                            --
                        end loop;
                    elsif l_object.object_type in ('TRIGGER') then
                        declare
                            l_body              clob;
                            l_enableStmt        clob;
                            l_idMetadataTrigger integer;
                            l_idMetadataEnable  integer;
                        begin
                            l_ddl := get_ddl(a_schemaName, l_object.object_name, l_object.object_type);
                            -- parse into body and enable statement
                            l_body       := substr(l_ddl, 1, regexp_instr(l_ddl, chr(10), 1, regexp_count(l_ddl, chr(10))));
                            l_enableStmt := substr(l_ddl, regexp_instr(l_ddl, chr(10), 1, regexp_count(l_ddl, chr(10))));
                            -- store metedata - body
                            l_partType          := gc_PARTTYPE_MAIN;
                            l_idMetadataTrigger := storeMetadata(l_body, 1);
                            -- enable/disable statement
                            l_partType         := gc_PARTTYPE_ALTER;
                            l_idMetadataEnable := storeMetadata(l_enableStmt, 2);
                            -- create dependency
                            insert into plsnap_MetadataDependency
                                (idmetadata, idmetadatareferenced)
                            values
                                (l_idMetadataEnable, l_idMetadataTrigger);
                        end;
                    else
                        l_ddl             := get_ddl(a_schemaName, l_object.object_name, l_object.object_type);
                        l_idMetadataDummy := storeMetadata(l_ddl, 1);
                    end if;
                    -- privileges
                    if l_object.object_type in ('TABLE', 'VIEW', 'PACKAGE', 'TYPE', 'PROCEDURE', 'FUNCTION', 'SEQUENCE', 'SYNONYM') then
                        -- privileges
                        l_partName        := null;
                        l_partType        := gc_PARTTYPE_PRIVILEGES;
                        l_idMetadataDummy := storeMetadata(null, -3);
                    end if;
                    --
                    commit;
                    --
                exception
                    when others then
                        logErrorForObject('populating metadata', l_object.owner, l_object.object_name, l_object.object_type);
                        rollback;
                        reraise();
                end;
            end if;
        end loop;
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.populateObjectsMetadata');
    end;

    ----------------------------------------------------------------------------
    procedure populateMetadataDependencies(a_idSnapshot in plsnap_Snapshot.idSnapshot%type) is
    begin
        -- NoFormat Start
        -- object dependnecies
        insert into plsnap_MetadataDependency
            (idmetadata, idMetadataReferenced)
            select src.idMetadata, tgt.idMetadata
              from dba_Dependencies dep
             inner join plsnap_Metadata src
                     on (src.idSnapshot = a_idSnapshot
                         -- partType = gc_PARTTYPE_MAIN
                         and src.part = 1
                         and dep.owner = src.schemaName
                         and dep.name = src.objectName
                         and dep.type = src.objectType)
             inner join plsnap_Metadata tgt
                     on (tgt.idSnapshot = a_idSnapshot
                         and tgt.partType = gc_PARTTYPE_PRIVILEGES
                         and dep.referenced_owner = tgt.schemaName
                         and dep.referenced_name = tgt.objectName
                         and dep.referenced_type = tgt.objectType)
        ;
        dbms_output.put_line('INFO> object -> object.privileges ='|| sql%rowcount);
        -- FKey -> PKey/UKey dependencies
        insert into plsnap_MetadataDependency
            (idmetadata, idMetadataReferenced)
            with deps as (
              select rcstr.owner as schemaName,
                     rcstr.table_name as ObjectName,
                     rcstr.constraint_name as partName,
                     kcstr.owner as schemaNameReferenced,
                     kcstr.table_name as objectNameReferenced,
                     kcstr.constraint_name as partNameReferenced,
                     decode(kcstr.constraint_type, 'P', 'PRIMARY KEY', 'U', 'UNIQUE') as partTypeReferenced
                from plsnap_Snapshot snap
               inner join plsnap_Schema snapSchm on (snapSchm.idDefinition = snap.idDefinition)
               inner join dba_constraints rcstr on (rcstr.owner = snapSchm.name and rcstr.constraint_type = 'R')
               inner join dba_constraints kcstr
                       on (kcstr.owner = rcstr.r_owner
                           and rcstr.r_Constraint_name = kcstr.constraint_name)
               where snap.idSnapshot = a_idSnapshot
            )
            select src.idMetadata, tgt.idMetadata
              from plsnap_Metadata src
             inner join deps
                     on (deps.schemaName = src.schemaName
                         and deps.objectName = src.objectName
                         and deps.partName = src.partName)
             inner join plsnap_Metadata tgt
                     on (tgt.idSnapshot = a_idSnapshot
                         and tgt.schemaName = deps.schemaNameReferenced
                         and tgt.objectName = deps.objectNameReferenced
                         and tgt.partName = deps.partNameReferenced
                         and tgt.partType = deps.partTypeReferenced)
             where src.idSnapshot = a_idSnapshot
               and src.partType = 'FOREIGN KEY'
        ;
        dbms_output.put_line('INFO> FKey -> PKey/UKey dependencies ='|| sql%rowcount);
        -- privilege -> table
        insert into plsnap_MetadataDependency
            (idmetadata, idMetadataReferenced)
            select src.idMetadata, tgt.idMetadata
              from plsnap_Metadata src
             inner join plsnap_Metadata tgt
                     on (tgt.idSnapshot = a_idSnapshot
                         -- partType = gc_PARTTYPE_MAIN
                         and tgt.part = 1
                         and tgt.schemaName = regexp_substr(src.objectName, '[^:]+', 1, 2)
                         and tgt.objectName = regexp_substr(src.objectName, '[^:]+', 1, 3)
                         and tgt.objectType = regexp_substr(src.objectName, '[^:]+', 1, 1))
             where src.objectType in ('TAB_PRIV', 'COL_PRIV')
               and src.idSnapshot = a_idSnapshot
        ;
        dbms_output.put_line('INFO> privilege -> table ='|| sql%rowcount);
        -- privileges group -> privilege
        insert into plsnap_MetadataDependency
            (idmetadata, idMetadataReferenced)
            select src.idMetadata, tgt.idMetadata
              from plsnap_Metadata tgt
             inner join plsnap_Metadata src
                     on (src.idSnapshot = a_idSnapshot
                         and src.partType = gc_PARTTYPE_PRIVILEGES
                         and src.schemaName = regexp_substr(tgt.objectName, '[^:]+', 1, 2)
                         and src.objectName = regexp_substr(tgt.objectName, '[^:]+', 1, 3)
                         and src.objectType = regexp_substr(tgt.objectName, '[^:]+', 1, 1))
             where tgt.objectType in ('TAB_PRIV', 'COL_PRIV')
               and tgt.idSnapshot = a_idSnapshot
        ;
        dbms_output.put_line('INFO> privileges group -> privilege ='|| sql%rowcount);
        -- \a index -> table
        insert into plsnap_MetadataDependency
            (idmetadata, idMetadataReferenced)
            select src.idMetadata, tgt.idMetadata
              from plsnap_Metadata src
             inner join dba_indexes ind
                     on (ind.owner = src.schemaName
                         and ind.index_name = src.objectName)
             inner join plsnap_Metadata tgt
                    on (tgt.idSnapshot = a_idSnapshot
                        and tgt.schemaName = ind.table_owner
                        and tgt.objectName = ind.table_name
                        and tgt.objectType = 'TABLE'
                        -- partType = gc_PARTTYPE_MAIN
                        and tgt.part = 1)
             where src.objectType = 'INDEX'
               and src.idSnapshot = a_idSnapshot
        ;
        dbms_output.put_line('INFO> index -> table ='|| sql%rowcount);
        -- indexes -> \a index
        insert into plsnap_MetadataDependency
            (idmetadata, idMetadataReferenced)
            select src.idMetadata, tgt.idMetadata
              from plsnap_Metadata src
             inner join dba_indexes ind
                     on (ind.owner = src.schemaName
                         and ind.table_name = src.objectName)
             inner join plsnap_Metadata tgt
                    on (tgt.idSnapshot = a_idSnapshot
                        and tgt.schemaName = ind.owner
                        and tgt.objectName = ind.index_name
                        and tgt.objectType = 'INDEX'
                        -- partType = gc_PARTTYPE_MAIN
                        and tgt.part = 1)
             where src.objectType = 'TABLE'
               and src.partType = gc_PARTTYPE_INDEXES
               and src.idSnapshot = a_idSnapshot
        ;
        dbms_output.put_line('INFO> indexs -> index ='|| sql%rowcount);
        -- data -> indexes
        insert into plsnap_MetadataDependency
            (idmetadata, idMetadataReferenced)
            select src.idMetadata, tgt.idMetadata
              from plsnap_Metadata src
             inner join plsnap_Metadata tgt
                     on (tgt.idSnapshot = a_idSnapshot
                         and tgt.schemaName = src.schemaName
                         and tgt.objectName = src.objectName
                         and tgt.objectType = 'TABLE'
                         and tgt.partType = gc_PARTTYPE_INDEXES)
             where src.objectType = 'TABLE'
               and src.partType = gc_PARTTYPE_DATA
               and src.idSnapshot = a_idSnapshot
        ;
        dbms_output.put_line('INFO> data -> indexes ='|| sql%rowcount);
        -- constraints -> data
        insert into plsnap_MetadataDependency
            (idmetadata, idMetadataReferenced)
            select src.idMetadata, tgt.idMetadata
              from plsnap_Metadata src
             inner join plsnap_Metadata tgt
                     on (tgt.idSnapshot = a_idSnapshot
                         and tgt.schemaName = src.schemaName
                         and tgt.objectName = src.objectName
                         and tgt.objectType = src.objectType
                         and tgt.partType = gc_PARTTYPE_DATA)
             where src.partType in ('PRIMARY KEY', 'UNIQUE', 'FOREIGN KEY', 'CHECK')
               and src.idSnapshot = a_idSnapshot
        ;
        dbms_output.put_line('INFO> constraints -> data ='|| sql%rowcount);
        -- privileges -> object
        insert into plsnap_MetadataDependency
            (idmetadata, idMetadataReferenced)
            select src.idMetadata, tgt.idMetadata
              from plsnap_Metadata src
             inner join plsnap_Metadata tgt
                     on (tgt.idSnapshot = a_idSnapshot
                         and tgt.schemaName = src.schemaName
                         and tgt.objectName = src.objectName
                         and tgt.objectType = src.objectType
                         -- partType = gc_PARTTYPE_MAIN
                         and tgt.part = 1)
             where src.partType  = 'PRIVILEGES'
               and src.idSnapshot = a_idSnapshot
        ;
        dbms_output.put_line('INFO> privileges -> object ='|| sql%rowcount);
        -- NoFormat End
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.populateMetadataDependencies');
    end;

    ----------------------------------------------------------------------------
    procedure populateMetadata(a_idSnapshot in plsnap_Snapshot.idSnapshot%type) is
        lrec_Snapshot plsnap_Snapshot%rowtype;
    begin
        -- check that scnapshot exists and is OK
        begin
            select * into lrec_Snapshot from plsnap_Snapshot where idSnapshot = a_idSnapshot;
        exception
            when no_data_found then
                raise_application_error(-20000, 'Snapshot idSnapshot="' || a_idSnapshot || '" not found.');
        end;
        -- for each schema registered in definition
        for l_snapshotSchema in (select *
                                   from plsnap_Schema
                                  where idDefinition = lrec_Snapshot.idDefinition
                                  order by name) loop
            -- privileges
            populateSystemPrivileges(a_idSnapshot, l_snapshotSchema.name);
            populateTablePrivileges(a_idSnapshot, l_snapshotSchema.name);
            populateColumnPrivileges(a_idSnapshot, l_snapshotSchema.name);
            -- objects
            populateObjectsMetadata(a_idSnapshot, l_snapshotSchema.name);
            --
        end loop;
        -- dependencies
        populateMetadataDependencies(a_idSnapshot);
        --
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.populateMetadata');
    end;

    ----------------------------------------------------------------------------
    procedure populateData(a_idSnapshot in plsnap_Snapshot.idSnapshot%type) is
    begin
        -- for each table
        for l_metadata in (select *
                             from plsnap_Metadata
                            where idSnapshot = a_idSnapshot
                              and ObjectType = 'TABLE'
                              and partType = gc_PARTTYPE_DATA) loop
            declare
                l_Cnt integer;
            begin
                execute immediate 'select nvl((select 1 from ' || l_metadata.schemaName || '.' || l_metadata.objectName ||
                                  ' where rownum = 1), 0) from dual'
                    into l_Cnt;
                if l_Cnt = 1 then
                    update plsnap_Metadata set hasData = 'Y' where idMetadata = l_metadata.idMetadata;
                    commit;
                    execute immediate 'create table ' || getDataTableName(l_metadata.idMetadata) || ' compress as select * from ' || l_metadata.schemaName || '.' ||
                                      l_metadata.objectName;
                end if;
                exception
                    when others then
                        logErrorForObject(null, l_metadata);
                        raise;
            end;
        end loop;
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.populateData');
    end;

    ----------------------------------------------------------------------------
    function getObjectsWOUnmetDeps(a_idSnapshot in plsnap_Snapshot.idSnapshot%type) return typ_MetadataTab is
        l_Result typ_MetadataTab;
    begin
        --
        select x.*
          BULK COLLECT
          into l_Result
          from plsnap_MetadataToRestore m
         inner join plsnap_Metadata x on (x.idMetadata = m.idMetadata)
         where 1 = 1
           and m.idSnapshot = a_idSnapshot
           and not EXisTS (
                -- there is no unmet dependency
                select 1
                  from plsnap_MetadataDependency dep
                 inner join plsnap_Metadatatorestore refObj on (refObj.idMetadata = dep.idMetadataReferenced)
                 where dep.idMetadata = m.idMetadata)
         order by schemaName, ObjectName, ObjectType, part;
        --
        return l_Result;
        --
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.getObjectsWOUnmetDeps');
    end;

    ----------------------------------------------------------------------------
    procedure changeCurrentSchema(a_schemaName in varchar2) is
    begin
        execute immediate 'alter session set current_schema = "' || a_schemaName || '"';
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.changeCurrentSchema');
    end;

    ----------------------------------------------------------------------------
    procedure transformToModify
    (
        a_metadata in plsnap_Metadata%rowtype,
        a_option   in varchar2
    ) is
    begin
        execute immediate replace(regexp_substr(a_metadata.ddl, 'ALTER TABLE (".*?"\.".*?") ADD CONSTRAINT (".*?")'), ' ADD ', ' MODifY ') || ' ' ||
                          a_option;
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.transformToModify');
    end;

    ----------------------------------------------------------------------------
    procedure executeDDL(a_metadata in plsnap_Metadata%rowtype) is
        l_currentSchema varchar2(255);
    begin
        l_currentSchema := sys_context('USERENV', 'CURRENT_SCHEMA');
        --
        changeCurrentSchema(a_metadata.schemaName);
        begin
            execute immediate a_metadata.ddl;
        exception
            -- handle various oracle bugs in implementation in dbms_metadata
            -- and some workarounds
            when e_fkrely_on_pknorely then
                -- pkey is no rely, with no rely fkey which was changed to rely afterwards
                -- oracle does not allow to create rely fkey on no rely pkey so, to recreate this we have to
                -- 1. create without rely
                execute immediate replace(a_metadata.ddl, ' RELY ', ' ');
                -- 2. modify with rely
                transformToModify(a_metadata, 'RELY');
                --
            when e_name_already_used then
                if a_metadata.objectType = 'INDEX' then
                    -- there is PKey UKey with same name - eat exception
                    null;
                else
                    raise;
                end if;
            when e_success_with_comp_error then
                if a_metadata.objectStatus = 'VALID' then
                    if a_metadata.objectType = 'VIEW' then
                        -- TODO: follow dependencies over synonym (add dependency) -> db link, as it my be local and part of snapshot definition)
                        logWarningForObject(null, a_metadata);
                    else
                        raise;
                    end if;
                else
                    -- object has been invalid - eat exception
                    null;
                end if;
            when e_partition_does_not_exist then
                if a_metadata.objectType = 'INDEX' and a_metadata.ddl like '%ALTER INDEX%' then
                    -- log warning and then
                    logWarningForObject(null, a_metadata);
                else
                    raise;
                end if;
            when others then
                if a_metadata.objectStatus != 'VALID' then
                    -- eat exceptions for not VALID objects
                    -- pretend that it is ok
                    null;
                else
                    raise;
                end if;
        end;
        changeCurrentSchema(l_currentSchema);
        --
        delete from plsnap_MetadataToRestore where idMetadata = a_metadata.idMetadata;
        commit;
        --
    exception
        when others then
            rollback;
            changeCurrentSchema(l_currentSchema);
            logErrorForObject('Applying ddl for',
                              a_metadata.schemaName,
                              a_metadata.objectName,
                              a_metadata.objectType,
                              a_metadata.idMetadata);
            reraise('Unexpected error in plsnap_impl.executeDDL');
    end;

    ----------------------------------------------------------------------------
    procedure loadData(a_metadata in plsnap_Metadata%rowtype) is
        l_Cnt integer;
    begin
        if a_metadata.hasData = 'Y' then
            -- TODO: disable indexes to increase performance
            execute immediate 'insert /*+ append optimizer_features_enable(''11.2.0.4'') */ into "' || a_metadata.schemaName || '"."' ||
                              a_metadata.objectName || '" select * from ' || getDataTableName(a_metadata.idMetadata);
            commit;
            -- TODO: enable indexes
        end if;
    exception
        when others then
            rollback;
            logErrorForObject('loading data', a_metadata.schemaName, a_metadata.objectName, a_metadata.objectType, a_metadata.idMetadata);
            reraise('Unexpected error in plsnap_impl.loadData');
    end;

    ----------------------------------------------------------------------------
    procedure recreateObject(a_metadata in plsnap_Metadata%rowtype) is
    begin
        --
        case a_metadata.partType
            when gc_PARTTYPE_DATA then
                loadData(a_metadata);
            when gc_PARTTYPE_INDEXES then
                -- do nothing - this part is only for dependencies
                null;
            when gc_PARTTYPE_PRIVILEGES then
                -- do nothing - this part is only for dependencies
                null;
            else
                executeDDL(a_metadata);
        end case;
        --
        delete from plsnap_MetadataToRestore where idMetadata = a_metadata.idMetadata;
        commit;
        --
    exception
        when others then
            logWarningForObject('recreateObject failed', a_metadata);
    end;

    ----------------------------------------------------------------------------
    -- Refactored procedure recreateObjects
    procedure recreateObjects(a_Snapshot in plsnap_Snapshot%rowtype) is
        l_lastObjToCreateCount pls_integer := -1;
        ltab_objectsToCreate   typ_MetadataTab;
        l_iteration            pls_integer := 1;
    begin
        ltab_objectsToCreate := getObjectsWOUnmetDeps(a_Snapshot.idSnapshot);
        while (ltab_objectsToCreate.count > 0 and l_iteration < gc_MAX_ITERATIONS) loop
            --
            dbms_output.put_line('-- iteration ' || l_iteration || ' objectsToCreate.count=' || ltab_objectsToCreate.count);
            for l_idx in 1 .. ltab_objectsToCreate.count loop
                recreateObject(ltab_objectsToCreate(l_idx));
            end loop;
            --
            l_lastObjToCreateCount := ltab_objectsToCreate.count;
            ltab_objectsToCreate   := getObjectsWOUnmetDeps(a_Snapshot.idSnapshot);
            l_iteration            := l_iteration + 1;
            --
        end loop;
        dbms_output.put_line('done');
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.recreateObjects');
    end recreateObjects;
    
    ----------------------------------------------------------------------------
    procedure drop_objects(p_schemaName in plsnap_Schema.name%type) is
        l_failed boolean := false;
    begin
        for cmd in (select 'drop ' || object_type || ' "' || owner || '"."' || object_name || '"' || case object_type
                               when 'TABLE' then
                                ' cascade constraints purge'
                               when 'TYPE' then
                                ' FORCE'
                           end as text,
                           owner,
                           object_type,
                           object_name
                      from dba_objects
                     where owner = p_schemaName
                       and object_type in ('TABLE', 'PACKAGE', 'SEQUENCE', 'VIEW', 'PROCEDURE', 'TYPE', 'SYNONYM', 'FUNCTION')
                       and object_name not like 'SYS_IOT%'
                     order by object_type, object_name) loop
            begin
                execute immediate cmd.text;
            exception 
                when others then 
                    logErrorForObject('Dropping object', cmd.owner, cmd.object_name, cmd.object_type, null);
                    l_failed := true;
            end;
        end loop;
        -- and cleanup orphaned package/type bodies
        for cmd in (select 'drop ' || object_type || ' "' || object_name || '"' as text, 
                           owner,
                           object_type, 
                           object_name
                      from dba_objects
                     where owner = p_schemaName
                       and object_type in ('PACKAGE BODY', 'TYPE BODY')
                     order by object_type, object_name) loop
            begin
                execute immediate cmd.text;
            exception 
                when others then 
                    logErrorForObject('Dropping object', cmd.owner, cmd.object_name, cmd.object_type, null);
                    l_failed := true;
            end;
        end loop;
        --
        if l_failed then
            raise_application_error(-20000, 'Fatal error: failed to drop object.');
        end if;
        --
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.drop_objects');
    end;

    ----------------------------------------------------------------------------
    -- public methods
    ----------------------------------------------------------------------------
    
    ----------------------------------------------------------------------------
    procedure createSnapshotDefinition(a_definitionName in plsnap_Definition.name%type) is
        pragma autonomous_transaction;
    begin
        insert into plsnap_Definition (name) values (a_definitionName) ;
        commit;
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.createSnapshotDefinition');
    end;


    ----------------------------------------------------------------------------
    procedure dropSnapshotDefinition(a_definitionName in plsnap_Definition.name%type) is
        pragma autonomous_transaction;
        lrec_Definition plsnap_Definition%rowtype;
    begin
        -- validate definition name
        select * into lrec_Definition from plsnap_Definition where name = a_definitionName;      
        -- drop all snapshots based on definition
        for l_snapshot in (select * from plsnap_Snapshot where idDefinition = lrec_Definition.idDefinition) loop
            dropSnapshot(l_snapshot.name);
        end loop;        
        -- delete definition
        delete from plsnap_Definition where name = a_definitionName;
        commit;
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.dropSnapshotDefinition');
    end;

    ----------------------------------------------------------------------------
    procedure addSchema
    (
        a_definitionName in plsnap_Definition.name%type,
        a_schemaName     in plsnap_Schema.name%type
    ) is
        pragma autonomous_transaction;
        lrec_Definition plsnap_Definition%rowtype;
    begin
        -- validate definition name
        select * into lrec_Definition from plsnap_Definition where name = a_definitionName;
        -- and insert
        insert into plsnap_Schema (idDefinition, name) values (lrec_Definition.idDefinition, a_schemaName);
        commit;
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.addSchema');
    end;


    ----------------------------------------------------------------------------
    procedure dropSchema
    (
        a_definitionName in plsnap_Definition.name%type,
        a_schemaName     in plsnap_Schema.name%type
    ) is
        pragma autonomous_transaction;
        lrec_Definition plsnap_Definition%rowtype;
    begin
        -- validate definition name
        select * into lrec_Definition from plsnap_Definition where name = a_definitionName;
        -- and delete
        delete from plsnap_Schema where idDefinition = lrec_Definition.idDefinition and name = a_schemaName;
        commit;
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.dropSchema');
    end;


----------------------------------------------------------------------------
    procedure createSnapshot
    (
        a_definitionName in plsnap_Definition.name%type,
        a_snapshotName   in plsnap_Snapshot.name%type
    ) is
        pragma autonomous_transaction;
        l_newIdSnapshot plsnap_Snapshot.idSnapshot%type;
        lrec_Definition plsnap_Definition%rowtype;
    begin
        -- validate definition name
        select * into lrec_Definition from plsnap_Definition where name = a_definitionName;
        -- store into row in table
        begin
            insert into plsnap_Snapshot
                (idDefinition, name, tsStatusChange, status)
            values
                (lrec_Definition.idDefinition, a_snapshotName, systimestamp, 'CREATING')
            returning idSnapshot into l_newIdSnapshot;
            commit;
        exception
            when dup_val_on_index then
                raise_application_error(-20000, 'Snapshot name="' || a_snapshotName || '" already exists.');
        end;
        -- initial dbms_metadata settings
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PRETTY', true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'FORCE', true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SEGMENT_ATTRIBUTES', true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'STORAGE', true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'TABLESPACE', true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'EMIT_SCHEMA', true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'REF_CONSTRAINTS', true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'CONSTRAINTS', true);
        dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'CONSTRAINTS_AS_ALTER', true);
        -- populate metadata
        populateMetadata(l_newIdSnapshot);
        -- populate data
        populateData(l_newIdSnapshot);
        --
        update plsnap_Snapshot set Status = 'OK' where idSnapshot = l_newIdSnapshot;
        commit;
        --
    exception
        when others then
            rollback;
            if l_newIdSnapshot is not null then
                update plsnap_Snapshot set Status = 'ERROR' where idSnapshot = l_newIdSnapshot;
                commit;
            end if;
            reraise('Unexpected error in plsnap_impl.createSnapshot');
    end;
    
    ----------------------------------------------------------------------------
    procedure dropSnapshot(a_snapshotName in plsnap_Snapshot.name%type) is
        pragma autonomous_transaction;
        l_idSnapshot plsnap_Snapshot.idSnapshot%type;
        l_tableName  user_tables.table_name%type;
    begin
        -- get snapshot by name
        select idSnapshot into l_idSnapshot from plsnap_Snapshot where name = a_snapshotName;
        -- drop tables
        for l_table in (select *
                          from plsnap_Metadata
                         where idSnapshot = l_idSnapshot
                           and ObjectType = 'TABLE'
                           and part = 1) loop
            l_tableName := getDataTableName(l_table.idMetadata);                
            for l_tableExists in (select * from user_tables where table_name = l_tableName) loop
                execute immediate 'drop table ' || l_tableName || ' purge';
            end loop;
        end loop;
        -- delete snapshot
        delete from plsnap_Snapshot where name = a_snapshotName;
        commit;
        --
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.dropSnapshot');
    end;

    ----------------------------------------------------------------------------
    procedure restoreFromSnapshot(a_snapshotName in plsnap_Snapshot.name%type) is
        lrec_Snapshot plsnap_Snapshot%rowtype;
    begin
        -- check that snapshot exists and is OK
        begin
            select * into lrec_Snapshot from plsnap_Snapshot where name = a_snapshotName;
        exception
            when no_data_found then
                raise_application_error(-20000, 'Snapshot name="' || a_snapshotName || '" not found.');
        end;
        -- foreach schema drop objects
        for l_snapshotSchema in (select * from plsnap_Schema where idDefinition = lrec_Snapshot.idDefinition) loop
            drop_objects(l_snapshotSchema.name);
        end loop;
        -- reset metadata to restore
        delete from plsnap_MetadataToRestore where idSnapshot = lrec_Snapshot.idSnapshot;
        insert into plsnap_MetadataToRestore
            (idSnapshot, idMetadata)
            select idSnapshot, idMetadata from plsnap_Metadata where idSnapshot = lrec_Snapshot.idSnapshot;
        commit;
        -- recreate objects
        recreateObjects(lrec_Snapshot);
        --
    exception
        when others then
            reraise('Unexpected error in plsnap_impl.restoreFromSnapshot');
    end;


end;
/
