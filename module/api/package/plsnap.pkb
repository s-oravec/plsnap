create or replace package body plsnap as

    ----------------------------------------------------------------------------
    procedure createSnapshotDefinition(definitionName in name_type) is
    begin
        plsnap_impl.createSnapshotDefinition(definitionName);
    end;

    ----------------------------------------------------------------------------
    procedure dropSnapshotDefinition(definitionName in name_type) is
    begin
        plsnap_impl.dropSnapshotDefinition(definitionName);
    end;

    ----------------------------------------------------------------------------
    procedure addSchema
    (
        definitionName in name_type,
        schemaName     in name_type
    ) is
    begin
        plsnap_impl.addSchema(definitionName, schemaName);
    end;

    ----------------------------------------------------------------------------
    procedure dropSchema
    (
        definitionName in name_type,
        schemaName     in name_type
    ) is
    begin
        plsnap_impl.dropSchema(definitionName, schemaName);
    end;

    ----------------------------------------------------------------------------
    procedure createSnapshot(
        definitionName in name_type,
        snapshotName   in name_type
    ) is
    begin
        plsnap_impl.createSnapshot(definitionName, snapshotName);
    end;

    ----------------------------------------------------------------------------
    procedure dropSnapshot(snapshotName in name_type) is
    begin
        plsnap_impl.dropSnapshot(snapshotName);
    end;

    ----------------------------------------------------------------------------
    procedure restoreFromSnapshot(snapshotName in name_type) is
    begin
        plsnap_impl.restoreFromSnapshot(snapshotName);
    end;

end;
/
