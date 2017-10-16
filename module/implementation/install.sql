rem Tables
prompt .. Creating table plsnap_Definition
@@table/plsnap_definition.sql

prompt .. Creating table plsnap_Snapshot
@@table/plsnap_snapshot.sql

prompt .. Creating table plsnap_Schema
@@table/plsnap_schema.sql

prompt .. Creating table plsnap_Metadata
@@table/plsnap_metadata.sql

prompt .. Creating table plsnap_MetadataDependency
@@table/plsnap_metadatadependency.sql

prompt .. Creating table plsnap_MetadataToRestore
@@table/plsnap_metadatatorestore.sql

rem Code Specifications
prompt .. Creating package plsnap_impl
@@package/plsnap_impl.pks

rem Code Bodies
prompt .. Creating package body plsnap_impl
@@package/plsnap_impl.pkb
