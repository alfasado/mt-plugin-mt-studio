package Developer::MTMLJob;
use strict;
use Developer::Util;
use MT::Util;

use base qw( MT::Object MT::Revisable );
__PACKAGE__->install_properties( {
    column_defs => {
        'id'         => 'integer not null auto_increment',
        'title'      => { type  => 'string',
                          size  => 255,
                          label => 'Name',
                          revisioned => 1,
                        },
        'text'       => { type  => 'text',
                          label => 'Text',
                          revisioned => 1,
                        },
        'text_php'   => { type  => 'text',
                          label => 'TextPHP',
                          revisioned => 1,
                        },
        'test_mtml'  => { type  => 'text',
                          label => 'TestMTML',
                          revisioned => 1,
                        },
        'interval'   => { type  => 'integer',
                          label => 'Trigger',
                          # revisioned => 1,
                        },
        'status'     => { type  => 'integer',
                          label => 'Status',
                          # revisioned => 1,
                        },
        'detail'     => { type  => 'string',
                          size  => 255,
                          label => 'Detail',
                          revisioned => 1,
                        },
        'nextrun_on' => { type  => 'datetime',
                          label => 'Run on',
                          # revisioned => 1,
                        },
        'lastrun_on' => { type  => 'datetime',
                          label => 'Last run',
                          # revisioned => 1,
                        },
        'priority'   => { type  => 'integer',
                          label => 'Priority',
                          # revisioned => 1,
                        },
        'app_ref'    => { type  => 'string',
                          size  => 255,
                          label => 'Application',
                          revisioned => 1,
                        },
        'evalscript'=> { type  => 'boolean',
                         label => 'Perl Script',
                         # revisioned => 1,
                        },
        'evalphp'   => { type  => 'boolean',
                         label => 'Eval PHP script',
                         # revisioned => 1,
                        },
        'tagkind'   => { type  => 'string',
                         size  => 25,
                         label => 'Kind of MT Tag',
                         revisioned => 1,
                       },
        'requires_login'=> { type  => 'boolean',
                         label => 'Requires Login',
                         # revisioned => 1,
                       },
        'basename'      => { type  => 'string',
                          size  => 255,
                          label => 'Basename',
                          # revisioned => 1,
                        },
        'is_default'    => { type  => 'boolean',
                          label => 'Default Handler',
                          # revisioned => 1,
                        },
        # allow (GET,POST,PUT,DELETE...) Default GET,POST
    },
    indexes => {
        'title'      => 1,
        'interval'   => 1,
        'nextrun_on' => 1,
        'lastrun_on' => 1,
        'priority'   => 1,
        'status'     => 1,
        'app_ref'    => 1,
        'basename'   => 1,
        'is_default' => 1,
    },
    datasource  => 'mtmljob',
    primary_key => 'id',
    meta  => 1,
    audit => 1,
} );

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

sub class_label {
    MT->component( 'Developer' )->translate( 'Custom Handler' );
}

sub class_label_raw {
    return 'Custom Handler';
}

sub class_label_plural {
    MT->component( 'Developer' )->translate( 'Custom Handlers' );
}

sub blog {
    return undef;
}

sub status_text {
    my $obj = shift;
    my $component = MT->component( 'Developer' );
    if ( $obj->status == 1 ) {
        return $component->translate( 'Disabled' );
    }
    return $component->translate( 'Enabled' );
}

sub save {
    my $obj = shift;
    my $basename = $obj->basename;
    if (! $basename ) {
        $basename = lc( Developer::Util::_dirify( $obj->title ) );
        $basename = 'custom_handler' if (! $basename );
        $basename = MT::Util::_get_basename( MT->model( 'mtmljob' ), lc( Developer::Util::_dirify( $basename ) ) );
    } else {
        $basename = lc( Developer::Util::_dirify( $basename ) );
    }
    $obj->basename( $basename );
    my $interval = $obj->interval;
    if ( (! $interval) || ( $interval != 10 ) ) {
        if ( ( $interval != 9 ) && ( $interval != 11 ) ) {
            $obj->app_ref( undef );
        } else {
            if ( $interval == 11 ) {
                $obj->app_ref( 'MT::App::DataAPI' );
            } else {
                $obj->app_ref( 'MT::App::Developer' );
            }
        }
    }
    # FIXME::move to pre_save
    $obj->SUPER::handle_max_revisions( MT->config( 'CustomHandlerMaxRevisions' ) );
    $obj->SUPER::save( @_ ) or return $obj->error( $obj->errstr );
    return 1;
}

sub interval_text {
    my $obj = shift;
    my $interval = $obj->interval;
    my $component = MT->component( 'Developer' );
    if (! defined $interval ) {
        return '-';
    }
    if ( $interval == 0 ) {
        return $component->translate( 'None' );
    } elsif ( $interval == 1 ) {
        return $component->translate( 'Every time' );
    } elsif ( $interval == 2 ) {
        return $component->translate( 'One time' );
    } elsif ( $interval == 3 ) {
        return $component->translate( 'Hourly' );
    } elsif ( $interval == 4 ) {
        return $component->translate( 'Daily' );
    } elsif ( $interval == 5 ) {
        return $component->translate( 'Weekly' );
    } elsif ( $interval == 6 ) {
        return $component->translate( 'Monthly' );
    } elsif ( $interval == 7 ) {
        return $component->translate( 'Callback' );
    } elsif ( $interval == 8 ) {
        return $component->translate( 'MT Tag' );
    } elsif ( $interval == 9 ) {
        return $component->translate( 'Application' );
    } elsif ( $interval == 10 ) {
        return $component->translate( 'Method' );
    } elsif ( $interval == 11 ) {
        return $component->translate( 'Data API Endpoint' );
    } elsif ( $interval == 12 ) {
        return 'config.yaml';
    }
}

sub interval_text_short {
    my $obj = shift;
    my $interval = $obj->interval;
    my $component = MT->component( 'Developer' );
    if (! defined $interval ) {
        return '-';
    }
    if ( $interval == 11 ) {
        return 'Data API';
    } elsif ( $interval == 9 ) {
        if ( $obj->is_default ) {
            return $component->translate( 'App' ) . ' - ' . $component->translate( 'Default' );
        }
        return $component->translate( 'App' );
    }
    return $obj->interval_text;
}

sub tagkind_text {
    my $obj = shift;
    my $interval = $obj->interval;
    my $component = MT->component( 'Developer' );
    if (! defined $interval ) {
        return '-';
    }
    if ( $interval == 8 ) {
        my $tagkind = $obj->tagkind;
        if ( $tagkind eq 'function' ) {
            return $component->translate( 'Function Tag' );
        } elsif ( $tagkind eq 'block' ) {
            return $component->translate( 'Block Tag' );
        } elsif ( $tagkind eq 'conditional' ) {
            return $component->translate( 'Conditional Tag' );
        } elsif ( $tagkind eq 'modifier' ) {
            return $component->translate( 'Global Modifier' );
        }
    } else {
        return '-';
    }
    return '';
}

1;