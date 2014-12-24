package Developer::AltTemplate;
use strict;

use base qw( MT::Object MT::Revisable );
__PACKAGE__->install_properties( {
    column_defs => {
        'id'      => 'integer not null auto_increment',
        'name'    => { type  => 'string',
                       size  => 255,
                       label => 'Name',
                       revisioned => 1,
                     },
        'text'    => { type  => 'text',
                       label => 'Text',
                       revisioned => 1,
                     },
        'status'  => { type  => 'integer',
                       label => 'Status',
                       # revisioned => 1,
                     },
        'app_ref' => { type  => 'string',
                       size  => 255,
                       label => 'Application',
                       # revisioned => 1,
                     },
        'template' => { type  => 'string',
                       size  => 255,
                       label => 'Template',
                       # revisioned => 1,
                     },
    },
    indexes => {
        'name'    => 1,
        'app_ref' => 1,
        'status'  => 1,
    },
    audit       => 1,
    datasource  => 'alttemplate',
    primary_key => 'id',
    meta  => 1,
} );

sub class_label {
    MT->component( 'Developer' )->translate( 'Alt Template' );
}

sub class_label_raw {
    return 'Alt Template';
}

sub class_label_plural {
    MT->component( 'Developer' )->translate( 'Alt Templates' );
}

sub author {
    my $obj = shift;
    my $author_id = $obj->created_by;
    return MT->translate( 'unknown' ) unless $author_id;
    my $author = MT->model( 'author' )->load( $author_id );
    if (! $author ) {
        $author = MT->model( 'author' )->new;
        $author->name( MT->translate( 'unknown' ) );
        $author->nickname( MT->translate( 'unknown' ) );
    }
    return $author;
}

sub blog {
    return undef;
}

sub compile {
    my $tmpl = shift;
    require MT::Template;
    require MT::Template::Context;
    require MT::Builder;
    my $template = MT::Template->new;
    my $ctx = MT::Template::Context->new;
    $template->name( $tmpl->name );
    $template->text( $tmpl->text );
    $ctx->{__stash}{ template } = $template;
    $tmpl->{ context } = $ctx;
    my $b = new MT::Builder;
    $b->compile( $template );
    if ( $template->errors ) {
        $tmpl->{ errors } = $template->errors;
    }
    return 1;
}

sub errors {
    my $tmpl = shift;
    $tmpl->{ errors } = shift if @_;
    $tmpl->{ errors };
}

sub status_text {
    my $obj = shift;
    my $component = MT->component( 'Developer' );
    if ( $obj->status == 1 ) {
        return $component->translate( 'Disabled' );
    }
    return $component->translate( 'Enabled' );
}

1;