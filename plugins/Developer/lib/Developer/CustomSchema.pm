package Developer::CustomSchema;
use strict;

use base qw( MT::Object );
__PACKAGE__->install_properties( {
    column_defs => {
        'author' => {
                'label' => 'Author Name',
                'size' => 255,
                'type' => 'string'
        },
        # 'cms' => 'text',
        'config' => 'text',
        'haslist' => {
                'label' => 'Listing',
                'type' => 'boolean'
        },
        'id' => 'integer not null auto_increment',
        'label' => {
                'label' => 'Label',
                'size' => 25,
                'type' => 'string'
        },
        'lang_id' => {
                'label' => 'Language',
                'size' => 25,
                'type' => 'string'
        },
        'lexicon' => 'text',
        # 'localize' => 'text',
        'module_id' => {
                'label' => 'Module ID',
                'size' => 25,
                'type' => 'string'
        },
        'name' => {
                'label' => 'Plugin ID',
                'size' => 255,
                'type' => 'string'
        },
        # 'php' => 'text',
        'pluginver' => {
                'label' => 'Version',
                'size' => 25,
                'type' => 'string'
        },
        'plural' => {
                'size' => 25,
                'type' => 'string'
        },
        'props' => 'text',
        'schema' => 'text',
        'schemaver' => {
                'label' => 'Schema Version',
                'size' => 25,
                'type' => 'string'
        }
    },
    indexes => {
        'author' => 1,
        'haslist' => 1,
        'label' => 1,
        'lang_id' => 1,
        'module_id' => 1,
        'name' => 1,
        'pluginver' => 1,
        'schemaver' => 1
    },
    datasource => 'customschema',
    class_type => 'customschema',
    primary_key => 'id',
    audit => 1,
} );

sub class_label {
    MT->component( 'Developer' )->translate( 'Custom Schema' );
}

sub class_label_plural {
    MT->component( 'Developer' )->translate( 'Custom Schemas' );
}

1;