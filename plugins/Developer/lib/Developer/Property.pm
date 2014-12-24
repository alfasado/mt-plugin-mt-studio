package Developer::Property;
use strict;

use base qw( MT::Object );
__PACKAGE__->install_properties( {
    column_defs => {
        'id'      => 'integer not null auto_increment',
        'name'    => 'string(255)',
        'text'    => 'text',
        'blog_id' => 'integer',
        'start'   => 'integer',
        'ttl'     => 'integer',
    },
    indexes => {
        'name'    => 1,
        'blog_id' => 1,
        'start'   => 1,
    },
    datasource  => 'property',
    primary_key => 'id',
} );

1;