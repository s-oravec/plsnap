create table plsnap_MetadataDependency (
  idMetadata           integer not null,
  idMetadataReferenced integer not null
);

comment on table plsnap_MetadataDependency is 'Metadata Dependency';

comment on column plsnap_MetadataDependency.idMetadata is 'Metadata';
comment on column plsnap_MetadataDependency.idMetadataReferenced is 'Referenced Metadata';

alter table plsnap_MetadataDependency
  add constraint plsnap_MtdtDep_pk
  primary key (idMetadata, idMetadataReferenced)
;

alter table plsnap_MetadataDependency
  add constraint plsnap_MtdtDep_Mtdt_fk
  foreign key (idMetadata)
  references plsnap_Metadata(idMetadata)
  on delete cascade
;

alter table plsnap_MetadataDependency
  add constraint plsnap_MtdtDep_MtdtRef_fk
  foreign key (idMetadataReferenced)
  references plsnap_Metadata(idMetadata)
  on delete cascade
;

create index plsnap_MtdtDep_BackRef on plsnap_MetadataDependency(idMetadataReferenced, idMetadata);
