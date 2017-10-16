rem Tables
prompt .. Dropping table plsnap_Definition
drop table plsnap_definition cascade constraints purge;

prompt .. Dropping table plsnap_Snapshot
drop table plsnap_snapshot cascade constraints purge;

prompt .. Dropping table plsnap_Schema
drop table plsnap_schema cascade constraints purge;

prompt .. Dropping table plsnap_Metadata
drop table plsnap_metadata cascade constraints purge;

prompt .. Dropping table plsnap_MetadataDependency
drop table plsnap_metadatadependency cascade constraints purge;

prompt .. Dropping table plsnap_MetadataToRestore
drop table plsnap_metadatatorestore cascade constraints purge;

rem Code Specifications
prompt .. Dropping package plsnap_impl
drop package plsnap_impl;
