create or replace package plsnap_impl authid current_user as

    subtype name_type is varchar2 (255);

    procedure createSnapshotDefinition(a_definitionName in plsnap_Definition.name%type);

    procedure dropSnapshotDefinition(a_definitionName in plsnap_Definition.name%type);

    procedure addSchema (
        a_definitionName in plsnap_Definition.name%type,
        a_schemaName     in plsnap_Schema.name%type
    );

    procedure dropSchema (
        a_definitionName in plsnap_Definition.name%type,
        a_schemaName     in plsnap_Schema.name%type
    );

    procedure createSnapshot (
        a_definitionName in plsnap_Definition.name%type,
        a_snapshotName   in plsnap_Snapshot.name%type
    );

    procedure dropSnapshot(a_snapshotName in plsnap_Snapshot.name%type);

    procedure restoreFromSnapshot(a_snapshotName in plsnap_Snapshot.name%type);

end;
/
