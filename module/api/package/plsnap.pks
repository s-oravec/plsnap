create or replace package plsnap authid current_user as

    subtype name_type is varchar2 (255);

    procedure createSnapshotDefinition(definitionName in name_type);

    procedure dropSnapshotDefinition(definitionName in name_type);

    procedure addSchema
    (
        definitionName in name_type,
        schemaName     in name_type
    );

    procedure dropSchema
    (
        definitionName in name_type,
        schemaName     in name_type
    );

    procedure createSnapshot(
        definitionName in name_type,
        snapshotName in name_type
    );

    procedure dropSnapshot(snapshotName in name_type);

    procedure restoreFromSnapshot(snapshotName in name_type);

end;
/
