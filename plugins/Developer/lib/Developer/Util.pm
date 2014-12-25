package Developer::Util;
use strict;
use base qw/Exporter/;

our @EXPORT_OK = qw(
    include_exclude_blogs utf8_on force_background_task app_ref2pkg id2app_ref _eval
    cancel_command translate_phrase can_access_to copy_to move_to app_ref2id get_app_script
    set_object_default set_entry_default association_link make_zip_archive _dirify _trim from_json
    data_api_setup_terms data_api_setup_args src2sub src2php rebuild_blogs rebuild_templates compile_test
);

use File::Temp qw( tempdir );

use Encode;
use MT::Util;
use MT::FileMgr;
use File::Basename;
use File::Find;
use File::Copy;
use File::Copy::Recursive;

sub path2relative {
    my ( $path, $blog ) = @_;
    my $app = MT->instance();
    my $static_file_path;
    if ( MT->version_number < 5 ) {
        $static_file_path = $app->static_file_path;
    } else {
        $static_file_path = $app->support_directory_path;
    }
    my $archive_path = $blog->archive_path;
    $archive_path = chomp_dir( $archive_path );
    my $site_path;
    $site_path = $blog->archive_path;
    $site_path = $blog->site_path unless $site_path;
    $site_path = chomp_dir( $site_path );
    if ( $^O eq 'MSWin32' ) {
        $path             =~ tr!\\!/!;
        $static_file_path =~ tr!\\!/!;
        $archive_path     =~ tr!\\!/!;
        $site_path        =~ tr!\\!/!;
    }
    $static_file_path = quotemeta( $static_file_path );
    $archive_path = quotemeta( $archive_path );
    $site_path = quotemeta( $site_path );
    $path =~ s/$static_file_path/%s/;
    $path =~ s/$site_path/%r/;
    if ( $archive_path ) {
        $path =~ s/$archive_path/%a/;
    }
    if ( $path =~ m!^https{0,1}://! ) {
        my $site_url = $blog->site_url;
        $site_url =~ s{/+$}{};
        $site_url = quotemeta( $site_url );
        $path =~ s/$site_url/%r/;
    }
    return $path;
}

sub chomp_dir {
    my $dir = shift;
    my @path = File::Spec->splitdir( $dir );
    $dir = File::Spec->catdir( @path );
    return $dir;
}

sub compile_test {
    my $code = shift;
    my $type = shift || 'perl';
    my $component = MT->component( 'Developer' );
    $type = lc( $type );
    $code =~ s/\r\n?/\n/g;
    if ( $type ne 'yaml' ) {
        $code = _trim( $code );
        $code =~ s/\n{1,}$//s;
    }
    my $tempdir = MT->config( 'TempDir' );
    $tempdir = tempdir( DIR => $tempdir );
    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    $tempdir =~ s!/$!! unless $tempdir eq '/';
    $fmgr->mkpath( $tempdir ) or return undef;
    my $libdir = File::Spec->catdir( $tempdir, 'lib', 'Developer' );
    $libdir =~ s!/$!! unless $libdir eq '/';
    $fmgr->mkpath( $libdir ) or return undef;
    if ( $type eq 'perl' ) {
        my $pm = File::Spec->catfile( $libdir, 'DeveloperTest.pm' );
        $code =~ s/^sub\s{0,}\{/sub __hdlr_test {/;
        $fmgr->put_data( "package Developer::DeveloperTest;\n\nuse strict;\n\n" . $code . "\n\n1;", $pm );
        unshift @INC, $libdir;
        eval {
            require $pm;
        };
        File::Path::rmtree( [ $tempdir ] );
        if ( my $error = $@ ) {
            return $error . $tempdir;
        }
        return 'OK';
    } elsif ( $type eq 'php' ) {
        if ( my $php_path = $component->get_config_value( 'developer_php_path' ) ) {
            my $php = File::Spec->catfile( $libdir, 'DeveloperTest.php' );
            $code = src2php( $code );
            $fmgr->put_data( $code, $php );
            my $cmd = $php_path . ' -l ' . $php;
            my $error = `$cmd`;
            File::Path::rmtree( [ $tempdir ] );
            if ( $error !~ m/^No\ssyntax\serrors/ ) {
                return $error;
            }
            return 'OK';
        }
    } elsif ( $type eq 'yaml' ) {
        eval {
            my $yaml = MT::Util::YAML::Load( $code . "\n" );
        };
        if ( my $error = $@ ) {
            return $error;
        }
        return 'OK';
    }
    return 'Unknown Type';
}

sub src2sub {
    my $data = shift;
    my $sub_name = shift || '';
    if ( $sub_name ) {
        $sub_name .= ' ';
    }
    $data = _trim( $data );
    if ( $data !~ m/^sub/m ) {
        $data = "sub ${sub_name}{\n" . $data . "\n}";
    } else {
        $data =~ s/^sub[^\{]{0,}/sub $sub_name/;
    }
    $data;
}

sub src2php {
    my $data = shift;
    $data = _trim( $data );
    if ( $data !~ m/^<\?/m ) {
        $data = "<?php\n" . $data;
    }
    $data;
}

sub utf8_on {
    my $text = shift;
    if (! Encode::is_utf8( $text ) ) {
        Encode::_utf8_on( $text );
    }
    return $text;
}

sub set_object_default {
    my ( $ctx, $obj ) = @_;
    my $app = MT->instance();
    my $user;
    if ( ( ref $app ) =~ /^MT::App/ ) {
        $user = $app->user;
    }
    if (! $user ) {
        $user = MT->model( 'author' )->load( undef, { limit => 1, 'sort' => 'id' } );
    }
    if ( $user ) {
        my $author_id = $user->id;
        if ( $obj->has_column( 'author_id' ) ) {
            if (! $obj->author_id ) {
                $obj->author_id( $author_id );
            }
        }
        if ( $obj->has_column( 'created_by' ) ) {
            if (! $obj->created_by ) {
                $obj->created_by( $author_id );
            }
        }
        if ( $obj->has_column( 'modified_by' ) ) {
            if (! $obj->modified_by ) {
                $obj->modified_by( $author_id );
            }
        }
    }
    if ( $obj->has_column( 'blog_id' ) ) {
        if (! $obj->blog_id ) {
            my $blog = $ctx->stash( 'blog' );
            if (! $blog ) {
                if ( ( ref $app ) =~ /^MT::App/ ) {
                    $blog = $app->blog;
                }
            }
            if ( $blog ) {
                $obj->blog_id( $blog->id );
            }
        }
    }
    return $obj;
}

sub set_entry_default {
    my $entry = shift;
    my $blog = $entry->blog;
    if (! $blog ) {
        $blog = MT::Blog->load( $entry->blog_id );
    }
    if (! $entry->status ) {
        $entry->status( $blog->status_default );
    }
    if (! $entry->allow_comments ) {
        $entry->allow_comments( $blog->allow_comments_default );
    }
    if (! $entry->allow_pings ) {
        $entry->allow_pings( $blog->allow_pings_default );
    }
    if (! $entry->class ) {
        $entry->class( 'entry' );
    }
    if (! $entry->authored_on ) {
        my @tl = MT::Util::offset_time_list( time, $blog );
        my $ts = sprintf '%04d%02d%02d%02d%02d%02d', $tl[5]+1900, $tl[4]+1, @tl[3,2,1,0];
        $entry->authored_on( $ts );
    }
    if ( $entry->allow_pings ) {
        if (! $entry->atom_id ) {
            $entry->atom_id( $entry->make_atom_id() );
        }
    }
    return $entry;
}

sub include_exclude_blogs {
    my ( $ctx, $args ) = @_;
    unless ( $args->{ blog_id } || $args->{ blog_ids } || $args->{ include_blogs } || $args->{ exclude_blogs } ) {
        $args->{ include_blogs } = $ctx->stash( 'include_blogs' );
        $args->{ exclude_blogs } = $ctx->stash( 'exclude_blogs' );
        $args->{ blog_ids } = $ctx->stash( 'blog_ids' );
    }
    my ( %blog_terms, %blog_args );
    $ctx->set_blog_load_context( $args, \%blog_terms, \%blog_args ) or return $ctx->error($ctx->errstr);
    my @blog_ids = $blog_terms{ blog_id };
    return if ! @blog_ids;
    if ( wantarray ) {
        return @blog_ids;
    } else {
        return \@blog_ids;
    }
}

sub rebuild_templates {
    my ( $template_ids, $force ) = @_;
    return unless $template_ids;
    return unless ref( $template_ids ) eq 'ARRAY';
    my @template_ids = @$template_ids;
    require MT::Request;
    my $r = MT::Request->instance;
    require MT::Template;
    my @templates = MT::Template->load( { id => \@template_ids } );
    return '' unless @templates;
    require MT::WeblogPublisher;
    my $pub = MT::WeblogPublisher->new;
    for my $template ( @templates ) {
        next if ( $r->cache( 'rebuildtrigger-rebuild-template_id:' . $template->id ) ) && ! $force;
        if ( my $blog_id = $template->blog_id ) {
            force_background_task( sub
                { $pub->rebuild_indexes( BlogID => $blog_id, Template => $template, Force => 1, ); } );
        }
        $r->cache( 'rebuildtrigger-rebuild-template_id:' . $template->id, 1 );
    }
}

sub rebuild_blogs {
    my ( $blog_ids, $ats ) = @_;
    require MT::Request;
    my $r = MT::Request->instance;
    require MT::WeblogPublisher;
    my $pub = MT::WeblogPublisher->new;
    for my $id ( @$blog_ids ) {
        if ( @$ats ) {
            for my $archive_type ( @$ats ) {
                next if ( $r->cache( 'rebuildtrigger-rebuild-blog_id:' . $id . ':' . $archive_type ) );
                if ( $archive_type !~ /\Aindex\z/i ) {
                    force_background_task( sub
                        { $pub->rebuild( BlogID => $id, ArchiveType => $archive_type, NoIndexes => 1 ); } );
                } else {
                    force_background_task( sub
                        { $pub->rebuild_indexes( BlogID => $id, Force => 1, ); } );
                }
                $r->cache( 'rebuildtrigger-rebuild-blog_id:' . $id . ':' . $archive_type, 1 );
            }
        } else {
            next if ( $r->cache( 'rebuildtrigger-rebuild-blog_id:' . $id ) );
            force_background_task( sub
                    { $pub->rebuild( BlogID => $id ); } );
            $r->cache( 'rebuildtrigger-rebuild-blog_id:' . $id, 1 );
        }
    }
    return '';
}

sub cancel_command {
    if ( MT->config( 'DoCommandInPreview' ) ) {
        return 0;
    }
    my $app = MT->instance;
    if ( ref ( $app ) eq 'MT::App::CMS' ) {
        my $mode = $app->mode;
        if ( $mode && ( $mode =~ /preview/ ) ) {
            return 1;
        }
    }
    return 0
}

sub force_background_task {
    my $app = MT->instance();
    my $fource = $app->config->BackgroundTasks;
    if ( ( ref $app ) =~ /^MT::App::/ ) {
        if ( ( $fource ) && (! $ENV{ FAST_CGI } ) && (! MT->config->PIDFilePath ) ) {
            my $default = $app->config->LaunchBackgroundTasks;
            $app->config( 'LaunchBackgroundTasks', 1 );
            my $res = MT::Util::start_background_task( @_ );
            $app->config( 'LaunchBackgroundTasks', $default );
            return $res;
        }
    }
    my ( $func ) = @_;
    return $func->();
    # return MT::Util::start_background_task( @_ );
}

sub translate_phrase {
    my $component = shift;
    my $lang = shift;
    my $handles = MT->request( 'l10n_handle' ) || {};
    my $h = $handles->{ $component->id };
    if (! defined $h ) {
        $h = $handles->{ $component->id } = $component->_init_l10n_handle( $lang ) || 0;
        MT->request( 'l10n_handle', $handles );
    }
    my ( $format, @args ) = @_;
    foreach ( @args ) {
        $_ = $_->() if ref( $_ ) eq 'CODE';
    }
    my $str;
    eval {
        if ( $h ) {
            $str = $h->maketext( $format, @args );
        }
        if ( !defined $str ) {
            $str = MT->translate( @_ );
        }
    };
    $str = $format unless $str;
    $str;
}

sub can_access_to {
    my ( $path, $blog, $read ) = @_;
    if ( $path =~ m/\.\./ ) {
        return 0;
    }
    my $app = MT->instance();
    my $can_access_to;
    if ( $read ) {
        $can_access_to = $app->config( 'CanReadFrom' );
    } else {
        $can_access_to = $app->config( 'CanWriteTo' );
    }
    if ( $can_access_to ) {
        if ( lc( $can_access_to ) eq 'any' ) {
            return 1;
        }
        my @paths = split( /,/, $can_access_to );
        for my $p ( @paths ) {
            $p = MT::Util::trim( $p );
            $p = quotemeta( $p );
            if ( $path =~ /^$p/ ) {
                return 1;
            }
        }
    }
    $path = File::Spec->canonpath( $path );
    my $tempdir = quotemeta( $app->config( 'TempDir' ) );
    my $importdir = quotemeta( $app->config( 'ImportPath' ) );
    # my $powercms_files_dir = quotemeta( chomp_dir( powercms_files_dir() ) );
    my $support_dir = quotemeta( $app->support_directory_path );
    if ( $path =~ /\A(?:$tempdir|$importdir|$support_dir)/i ) {
        return 1;
    }
    if ( defined $blog ) {
        my $site_path = quotemeta( $blog->site_path );
        if ( $path =~ /^$site_path/ ) {
            return 1;
        }
    }
    return 0;
}

sub copy_to {
    my ( $from, $to, $move ) = @_;
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    my $dir = File::Basename::dirname( $to );
    $dir =~ s!/$!! unless $dir eq '/';
    unless ( $fmgr->exists( $dir ) ) {
        $fmgr->mkpath( $dir ) or MT->log( MT->translate( "Error making path '[_1]': [_2]",
                                          $to, $fmgr->errstr ) );
    }
    if (! $move ) {
        if ( File::Copy::Recursive::rcopy( $from, $to ) ) {
            return 1;
        }
    } else {
        if ( -f $from ) {
            if ( File::Copy::move( $from, $to ) ) {
                return 1;
            }
        } elsif ( -d $from ) {
            if ( File::Copy::Recursive::dirmove( $from, $to ) ) {
                return 1;
            }
        }
    }
    return 0;
}

sub move_to {
    my ( $from, $to ) = @_;
    return copy_to( $from, $to, 1 );
}

sub association_link {
    my ( $app, $author, $role, $blog ) = @_;
    eval{
        require MT::Association;
        my $assoc = MT::Association->link( $author => $role => $blog );
        if ( $assoc ) {
            my $log = MT::Log->new;
            my $msg = { message => $app->translate(
                        "[_1] registered to the blog '[_2]'",
                        $author->name,
                        $blog->name
                    ),
                    level    => MT::Log::INFO(),
                    class    => 'author',
                    category => 'new',
                    blog_id  => $blog->id,
            };
            if ( ref $app =~ /^MT::App::/ ) {
                $msg->{ ip } = $app->remote_ip;
                if ( my $user = $app->user ) {
                    $log->author_id( $user->id );
                }
            }
            $log->set_values( $msg );
            $log->save or die $log->errstr;
            return $assoc;
        }
    };
    return undef;
}

sub make_zip_archive {
    my ( $directory, $out, $encoding ) = @_;
    eval { require Archive::Zip } || return undef;
    my $archiver = Archive::Zip->new();
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    my $dir = dirname( $out );
    $dir =~ s!/$!! unless $dir eq '/';
    unless ( $fmgr->exists( $dir ) ) {
        $fmgr->mkpath( $dir ) or return undef;
    }
    if (-f $directory ) {
        my $basename = File::Basename::basename( $directory );
        $archiver->addFile( utf8_on( $directory ), $basename );
        return $archiver->writeToFileNamed( $out );
    }
    $directory =~ s!/$!!;
    my @wanted_files;
    File::Find::find( sub { push( @wanted_files, $File::Find::name ) unless (/^\./) || ! -f; }, $directory );
    $encoding ||= 'utf-8';
    my $re = qr{^(?:\Q$directory\E)?[/\\]*};
    for my $file ( @wanted_files ) {
        $file = Encode::encode( $encoding, $file )
            if Encode::is_utf8( $file );
        my $new = $file;
        $new =~ s/$re//;
        $archiver->addFile( $file, $new );
    }
    return $archiver->writeToFileNamed( $out );
}

sub _dirify {
    my $s = $_[0];
    return '' unless defined $s;
    my $sep;
    if ( ( defined $_[1] ) && ( $_[1] ne '1' ) ) {
        $sep = $_[1];
    } else {
        $sep = '_';
    }
    $s =~ s!\.!$sep!gs;
    $s = MT::Util::xliterate_utf8( $s );
    $s = MT::Util::remove_html( $s );
    $s =~ s!&[^;\s]+;!!gs;
    $s =~ s!\-!_!gs;
    $s =~ s![^\w\s-]!!gs;
    $s =~ s!\s+!$sep!gs;
    return $s;
}

sub _trim {
    my $string = shift;
    $string = MT::Util::trim( $string );
    $string =~ s/^\n+//;
    $string =~ s/\n+$//;
    return MT::Util::trim( $string );
}

sub _eval {
    my $code = shift;
    eval ( $code );
    if ( $@ ) {
        return $@;
    }
    return undef;
}

sub app_ref2id {
    my $app_ref = shift;
    my $all_apps = shift;
    if (! $all_apps ) {
        $all_apps = MT->registry( 'applications' );
    }
    for my $mtapp( keys %$all_apps ) {
        if ( my $handler = $all_apps->{ $mtapp }->{ handler } ) {
            if ( $app_ref eq $handler ) {
                return $mtapp;
            }
        }
    }
    return '';
}

sub id2app_ref {
    my $app_id = shift;
    my $all_apps = shift;
    if (! $all_apps ) {
        $all_apps = MT->registry( 'applications' );
    }
    for my $mtapp( keys %$all_apps ) {
        if ( $app_id eq $mtapp ) {
            return $all_apps->{ $mtapp }->{ handler };
        }
    }
    return '';
}

sub app_ref2pkg {
    my $app_ref = shift;
    my @split_app = split( /::/, $app_ref );
    return $split_app[ scalar( @split_app ) - 1 ];
}

sub get_app_script {
    my $app_id = shift;
    my $all_apps = shift;
    if ( $app_id =~ /^MT::/ ) {
        $app_id = app_ref2id( $app_id );
    }
    if (! $all_apps ) {
        $all_apps = MT->registry( 'applications' );
    }
    for my $mtapp( keys %$all_apps ) {
        if ( $app_id eq $mtapp ) {
            if ( my $script = $all_apps->{ $mtapp }->{ script } ) {
                my $freq = MT->handler_to_coderef( $script );
                if ( $script = $freq->() ) {
                    return $script;
                }
            }
        }
    }
    return '';
}

sub data_api_setup_terms {
    my ( $app, $endpoint, $model ) = @_;
    my $terms = {};
    if ( MT->model( $model )->has_column( 'blog_id' ) ) {
        if ( my $blog = $app->blog ) {
            $terms->{ blog_id } = $blog->id;
        }
    }
    if ( MT->model( $model )->has_column( 'class' ) ) {
        $terms->{ class } = '*';
    }
    my $filter_cols = MT->model( $model )->column_names;
    for my $col ( @$filter_cols ) {
        if ( $app->param( $col ) ) {
            $terms->{ $col } = $app->param( $col );
        }
    }
    if ( $model eq 'log' ) {
        if ( my $level = $app->param( 'level' ) ) {
            if ( $level =~ /[^0-9]/ ) {
                $level = uc( $level );
                $terms->{ level } = _str_to_level( $level );
            }
        }
    }
    return $terms;
}

sub _str_to_level {
    my $level = shift;
    if ( $level eq 'INFO' ) {
        return 1;
    } elsif ( $level eq 'WARNING' ) {
        return 2;
    } elsif ( $level eq 'ERROR' ) {
        return 4;
    } elsif ( $level eq 'SECURITY' ) {
        return 8;
    } elsif ( $level eq 'DEBUG' ) {
        return 16;
    }
    return 1; # INFO
}

sub data_api_setup_args {
    my ( $app, $endpoint, $model, $sort_cols ) = @_;
    my $args;
    my $params = $endpoint->{ default_params } || {};
    my $sort_order = $params->{ sortOrder } || 'descend';
    my $sort_by = $params->{ sortBy } || 'id';
    if (! $sort_cols ) {
        if ( $model ) {
            $sort_cols = MT->model( $model )->column_names;
        }
    }
    if ( my $sortBy = $app->param( 'sortBy' ) ) {
        if ( defined $sort_cols ) {
            if ( grep( /^$sortBy$/, @$sort_cols ) ) {
                $sort_by = $sortBy;
            }
        }
    }
    if ( my $sortOrder = $app->param( 'sortOrder' ) ) {
        if ( $sortOrder eq 'ascend' ) {
            $sort_order = $sortOrder;
        }
    }
    $args->{ sort_by } = $sort_by;
    $args->{ direction } = $sort_order;
    my $limit = $params->{ limit } || MT->config( 'DataAPIDefaultLimit' ) || 25;
    if ( $app->param( 'limit' ) ) {
        $limit = $app->param( 'limit' ) + 0;
    }
    my $offset = $params->{ offset } || 0;
    if ( $app->param( 'offset' ) ) {
        $offset = $app->param( 'offset' ) + 0;
    }
    $args->{ limit } = $limit;
    $args->{ offset } = $offset;
    return $args;
}

sub from_json {
    my ( $value, $args ) = @_;
    require JSON;
    return JSON::from_json( $value, $args );
}

1;