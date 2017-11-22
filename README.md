# plsnap

Creates and manages Snapshots of schemas - without using DataPump, because sometimes that's just what you need.

Currently supports snapshoting and restoring of multischema PL/SQL apps containing

- tables
- indexes
- constraints
- views
- stored procedures - packages, functions, procedures
- triggers
- synonyms

User with **plsnap** deployed has to have really strong privileges - **DBA** role is the bestest. Otherwise you have to grant explicitly privileges on objects owned by `SYS`, as these cannot be granted even with `grant any object privilege` (read docs for detailed info)

# API

## createSnapshotDefinition

Creates **Snapshot Definition**.

### Params

- **definitionName** - unique definition name

## dropSnapshotDefinition

Drops **Snapshot Definition** and all **Snapshots** created with this definition.

- **definitionName** - definition name 

## addSchema

Adds schema to **Snapshot Definition**

- **definitionName** - definition name
- **schemaName** - schema name

## dropSchema

Removes schema from **Snapshot Definition**

- **definitionName** - definition name
- **schemaName** - schema name

## createSnapshot

Creates **Snapshot** of schemas in **Snapshot Definition**

- **definitionName** - definition name
- **snapshotName** - unique snaphsot name

## dropSnapshot

Drops existing **Snapshot**

- **snapshotName** snapshot name

## restoreFromSnapshot

Restore from **Snapshot**

1. Drops all objects in schemas
2. Recreates them from **Snapshot**

- **snapshotName** - snapshot name

# Sample usage

```
prompt Create Snapshot Definition "Oracle Sample Schemas"
exec plsnap.createSnapshotDefinition(definitionName => 'Oracle Sample Schemas');

prompt Add SCOTT schema to Snapshot Definition
exec plsnap.addSchema(definitionName => 'Oracle Sample Schemas', schemaName => 'SCOTT');

prompt And create Snapshot "Before"
exec plsnap.createSnapshot(definitionName => 'Oracle Sample Schemas', snapshotName => 'Before');

prompt Before destroy
select count(*) from scott.dept;

prompt Destroy schema 
drop table scott.dept cascade constraints purge;

prompt PANIC!!!
select count(*) from scott.dept;

prompt Restore
exec plsnap.restoreFromSnapshot(snapshotName => 'Before');

prompt Yay!
select count(*) from scott.dept;
```

# TODO

- add snapshot size info
- add some views for easier management
- add tests
- add some pretty outputs
- add debug calls
- implement other object types
    - materialzied views
    - ...
- implement usage from different schema - not implemented or tested
