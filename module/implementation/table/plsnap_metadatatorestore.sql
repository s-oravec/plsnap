create table plsnap_MetadataToRestore (
  idSnapshot integer not null,
  idMetadata integer not null,
  constraint plsnap_MtdtRstr_pk primary key (idSnapshot, idMetadata)
) organization index
;

comment on table plsnap_MetadataToRestore is 'Metadata to be restored in Snapshot restore action';

comment on column plsnap_MetadataToRestore.idSnapshot is 'Snapshot';
comment on column plsnap_MetadataToRestore.idMetadata is 'Metadata';

alter table plsnap_MetadataToRestore
  add constraint plsnap_MtdtRstr_Snap_fk
  foreign key (idSnapshot)
  references plsnap_Snapshot(idSnapshot)
  on delete cascade
;

alter table plsnap_MetadataToRestore
  add constraint plsnap_MtdtRstr_Mtdt_fk
  foreign key (idMetadata)
  references plsnap_Metadata(idMetadata)
  on delete cascade
;

