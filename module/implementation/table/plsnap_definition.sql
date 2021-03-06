create table plsnap_Definition (
  idDefinition integer generated by default as identity,
  name         varchar2(255) not null
);

comment on table plsnap_Definition is ' Definition';

comment on column plsnap_Definition.idDefinition is 'Surrogate key';
comment on column plsnap_Definition.name is 'Unique name';

alter table plsnap_Definition
  add constraint plsnap_Def_pk
  primary key (idDefinition)
;

alter table plsnap_Definition
  add constraint plsnap_Def_uk1
  unique (name)
;

