package Developer::Tags;

use strict;
no warnings 'redefine';
use Data::Dumper;
{
    package Data::Dumper;
    sub qquote { return shift; }
}
$Data::Dumper::Useperl = 1;

use MT::Util qw( encode_html epoch2ts );
use Developer::Util qw( include_exclude_blogs utf8_on force_background_task rebuild_templates
                        rebuild_blogs cancel_command translate_phrase can_access_to copy_to move_to
                        set_object_default set_entry_default association_link );
use Time::HiRes;
use MIME::Base64;
use MT::Log;
use HTTP::Request::Common;
use LWP::UserAgent;
# use JSON qw/decode_json/;
use File::Path;

sub _hdlr_run_callbacks {
    my ( $ctx, $args, $cond ) = @_;
    return '' if cancel_command();
    my $app = MT->instance;
    my $name = $args->{ name } || return '';
    my $res = $app->run_callbacks( ref( $app ) . '::' . $name, $app, @_ );
    if ( $args->{ need_result } ) {
        return $res;
    }
    return '';
}

sub _hdlr_perlscript {
    my ( $ctx, $args, $cond ) = @_;
    if (! MT->config( 'AllowPerlScript' ) ) {
        my $component = MT->component( 'Developer' );
        return $ctx->error( $component->translate(
            'Please set the environment variable AllowPerlScript.' ) );
    }
    return '' if cancel_command();
    my $print = $args->{ 'print' };
    if (! $print ) {
        $print = $args->{ 'echo' };
    }
    my $out = _hdlr_pass_tokens( @_ );
    $out = MT->instance->translate_templatized( $out );
    if ( $out !~ m/sub\s{0,}\{/m ) {
        $out = "sub {\n" . $out . "\n}";
    }
    my $freq = MT->handler_to_coderef( $out );
    $freq = $freq->( $ctx, $args, $cond );
    return $freq if $print;
    return '';
}

sub _hdlr_redirect {
    my ( $ctx, $args, $cond ) = @_;
    my $url = $args->{ url };
    MT->instance->redirect( $url );
}

sub _hdlr_throw_sql {
    my ( $ctx, $args, $cond ) = @_;
    my $component = MT->component( 'Developer' );
    if (! MT->config( 'AllowThrowSQL' ) ) {
        return $ctx->error( $component->translate(
            'Please set the environment variable AllowThrowSQL.' ) );
    }
    my $query = $args->{ query } || return '';
    require MT::Object;
    my $driver = MT::Object->driver;
    my $dbh = $driver->{ fallback }->{ dbh };
    my $sth = $dbh->prepare( $query );
    return $ctx->error( 'Error in query: ' . $dbh->errstr ) if $dbh->errstr;
    my $do = $sth->execute();
    return $ctx->error( 'Error in query: ' . $sth->errstr ) if $sth->errstr;
    return '';
}

sub _hdlr_ml_job {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    my $component = MT->component( 'Developer' );
    my $name = $args->{ name };
    if (! $name ) {
        $name = $args->{ title };
    }
    my $id = $args->{ id };
    if ( (! $name ) && (! $id ) ) {
        return '';
    }
    my $job;
    if ( $id ) {
        $job = MT->model( 'mtmljob' )->load( $id );
    } elsif ( $name ) {
        $job = MT->model( 'mtmljob' )->load( { title => $name } );
    }
    if ( (! $job ) || ( $job->status != 2 ) ) {
        return '';
    }
    my $template = $job->text;
    $template = $app->translate_templatized( $template );
    $ctx->stash( 'mtmljob', $job );
    require MT::Builder;
    my $build = MT::Builder->new;
    my $tokens = $build->compile( $ctx, $template )
        or $app->log( $component->translate(
            'Parse error: [_1]', $build->errstr ) );
    defined( my $out = $build->build( $ctx, $tokens ) )
        or $app->log( $component->translate(
            'Build error: [_1]', $build->errstr ) );
    if ( $app->config( 'AllowPerlScript' ) ) {
        # return '' if cancel_command();
        if ( $job->evalscript ) {
            if ( $out !~ m/sub\s{0,}\{/m ) {
                $out = "sub {\n" . $out . "\n}";
            }
            my $freq = MT->handler_to_coderef( $out );
            $freq = $freq->( $ctx, $args, $cond );
            return $freq;
        }
    }
    return $out;
}

sub _hdlr_ml_job_title {
    my ( $ctx, $args, $cond ) = @_;
    my $job = $ctx->stash( 'mtmljob' );
    return '' unless $job;
    return $job->title;
}

sub _hdlr_create_object {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance();
    my $component = MT->component( 'Developer' );
    if (! MT->config( 'AllowCreateObject' ) ) {
        return $ctx->error( $component->translate(
            'Please set the environment variable AllowCreateObject.' ) );
    }
    my $model = $args->{ model };
    return '' if $model eq 'author';
    return '' if $model eq 'permission';
    my $allowed = MT->config( 'AllowCreateObject' );
    if ( lc( $allowed ) ne 'any' ) {
        my @objs = split( /,/, $allowed );
        if (! grep( /^$model$/, @objs ) ) {
            return '';
        }
    }
    my $values = $args->{ 'values' };
    my $obj = MT->model( $model )->new;
    $obj->set_values( $values );
    $obj = set_object_default( $ctx, $obj );
    if ( ( ( ref $obj ) eq 'MT::Entry' ) || ( ( ref $obj ) eq 'MT::Page' ) ) {
        my $blog_id = $values->{ blog_id };
        $obj->blog_id( $blog_id );
        $obj = set_entry_default( $obj );
    }
    my $run_callbacks = $args->{ 'callbacks' };
    my $logging = $args->{ 'logging' };
    if ( ( ref $app ) !~ /^MT::App/ ) {
        $run_callbacks = undef;
    }
    require Storable;
    my $original = Storable::dclone( $obj );
    $obj->save or return $ctx->error( $obj->errstr );
    if ( $run_callbacks ) {
        $app->run_callbacks( 'cms_post_save.' . $model, $app, $obj, $original );
    }
    if ( $logging ) {
        my $message;
        if ( ( $obj->has_column( 'author_id' ) ) && $obj->author_id ) {
            if ( my $author = MT->model('author')->load( $obj->author_id ) ) {
                $message = $component->translate( '\'[_1]\' created by \'[_2]\'', $obj->class_label, $author->name );
            }
        } else {
            if ( ( ref $app ) =~ /^MT::App::/ ) {
                if ( my $author = $app->user ) {
                    $message = $component->translate( '\'[_1]\' created by \'[_2]\'', $obj->class_label, $author->name );
                }
            }
        }
        if (! $message ) {
            $message = $component->translate( '\'[_1]\' created by \'[_2]\'', $obj->class_label, MT->translate( 'unknown' ) );
        }
        if ( ( $obj->has_column( 'blog_id' ) ) && $obj->blog_id ) {
            $args->{ blog_id } = $obj->blog_id;
        }
        $args->{ message } = $message;
        _hdlr_log( $ctx, $args, $cond );
    }
    if ( my $need_result = $args->{ need_result } ) {
        if ( ( $need_result eq '1' ) && ( $obj->has_column( 'id' ) ) ) {
            return $obj->id;
        } else {
            if ( $obj->has_column( $need_result ) || ( $need_result eq 'permalink' ) ) {
                return $obj->$need_result;
            }
        }
        return 1;
    }
    return '';
}

sub _hdlr_set_user_role {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance();
    if ( ( ref $app ) !~ /^MT::App::/ ) {
        return '';
    }
    my $user; # = $app->user;
    if (! $user ) {
        if ( my $author_id = $args->{ author_id } ) {
            $user = MT->model( 'author' )->load( $author_id );
        }
    }
    if (! $user ) {
        return '';
    }
    my $blog_id = $args->{ blog_id };
    my $blog;
    if ( $blog_id ) {
        $blog = MT::Blog->load( $blog_id );
    } else {
        $blog = $app->blog || $ctx->stash( 'blog' );
    }
    if (! $blog ) {
        return '';
    }
    my $role;
    if ( my $name = $args->{ role } ) {
        if ( $args->{ translate } ) {
            $name = MT->translate( $name );
        }
        $role = MT->model( 'role' )->load( { name => $name } );
    } elsif ( my $role_id = $args->{ role_id } ) {
        $role = MT->model( 'role' )->load( $role_id );
    }
    if (! $role ) {
        return '';
    }
    if ( association_link( $app, $user, $role, $blog ) ) {
        if ( $args->{ need_result } ) {
            return 1;
        }
    }
    return '';
}

sub _hdlr_get_onetimetoken {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance();
    my $sess = MT->model( 'session' )->new;
    my $token = $app->make_magic_token;
    $sess->id( $token );
    $sess->kind( 'DT' );
    $sess->start( time );
    $sess->save or die $sess->errstr;
    return $token;
}

sub _hdlr_if_valid_token {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance();
    my $sess_name = $args->{ name } || 'magic_token';
    my $session_id = $args->{ value };
    if (! $session_id ) {
        $session_id = $app->param( $sess_name );
    }
    if (! $session_id ) {
        return 0;
    }
    my $sess = MT->model( 'session' )->load( $session_id );
    if ( $sess ) {
        my $ttl = MT->config( 'OnetimeTokenTTL' );
        if ( ( time - $sess->start ) > $ttl ) {
            $sess->remove or die $sess->errstr;
            return 0;
        }
        $sess->remove or die $sess->errstr;
        return 1;
    }
    return 0;
}

sub _hdlr_if_useace {
    my ( $ctx, $args, $cond ) = @_;
    my $component = MT->component( 'Developer' );
    return $component->get_config_value( 'developer_job_use_ace' );
}

sub _hdlr_cms_context {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance();
    my $author = $app->user;
    my $blog = $app->blog;
    my $q = $app->param;
    my $type = $q->param( '_type' );
    my $mode = $q->param( '__mode' );
    my $reedit = $q->param( 'reedit' );
    my $id = $q->param( 'id' );
    my $tokens = $ctx->stash( 'tokens' );
    my $builder = $ctx->stash( 'builder' );
    local $ctx->{ __stash }{ blog } = $blog;
    local $ctx->{ __stash }{ blog_id } = $blog->id if $blog;
    my $class = MT->model( $type );
    my $entry = MT->request( 'cms_cache_entry' );
    unless ( defined $entry ) {
        $entry = $class->load( $id ) if ( ( $id ) && ( $mode eq 'view' )
                                                    && ( ( $type eq 'entry') || ( $type eq 'page') ) );
        MT->request( 'cms_cache_entry', $entry ) if ( $entry );
    }
    $entry = $class->new if ( (! $id ) && ( $mode eq 'view' )
                                          && ( ( $type eq 'entry') || ( $type eq 'page') ) );
    if ( defined $entry ) {
        if ( $reedit ) {
            my @clumns = $entry->column_names;
            for my $key ( $q->param ) {
                if ( grep( /^$key$/, @clumns ) ) {
                    $entry->$key( $q->param ( $key ) );
                } else {
                    if ( $key eq 'tags' ) {
                        my $tag_delim = chr( $author->entry_prefs->{ tag_delim } );
                        my @tags = MT::Tag->split( $tag_delim, $q->param ( $key ) );
                        $entry->set_tags( @tags );
                    }
                }
            }
        }
    }
    my $category = MT->request( 'cms_cache_category' );
    unless ( defined $category ) {
        $category = $class->load( $id ) if ( ( $id ) && ( $mode eq 'view' )
                                          && ( ( $type eq 'category') || ( $type eq 'folder') ) );
        MT->request( 'cms_cache_category', $category ) if ( $category );
    }
    local $ctx->{ __stash }{ entry } = $entry if ( defined $entry );
    local $ctx->{ __stash }{ category } = $category if ( $type eq 'category' );
    local $ctx->{ __stash }{ folder } = $category if ( $type eq 'folder' );
    local $ctx->{ __stash }{ author } = $app->user;
    my $out = $builder->build( $ctx, $tokens, $cond );
    $out;
}

sub _hdlr_if_request_method {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance();
    if ( ( ref $app ) !~ /^MT::App::/ ) {
        return 0;
    }
    my $value = $app->request_method;
    $args->{ name } = 'request_method';
    $ctx->{ __stash }{ vars }{ request_method } = $value;
    return MT::Template::Tags::Core::_hdlr_if( $ctx, $args, $cond );
}

sub _hdlr_request_method {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance();
    if ( ( ref $app ) !~ /^MT::App::/ ) {
        return '';
    }
    return $app->request_method;
}

sub _hdlr_if_user_role {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance();
    if ( ( ref $app ) !~ /^MT::App::/ ) {
        return 0;
    }
    my $author = $app->user;
    if ( my $author_id = $args->{ author_id } ) {
        $author = MT->model( 'author' )->load( { id => $author_id } );
    }
    return 0 unless $author;
    # TODO::MTA(by Group)
    if ( $args->{ include_superuser } ) {
        return 1 if $author->is_superuser;
    }
    my $blog_id = $args->{ blog_id };
    unless ( $blog_id ) {
        $blog_id = ( $app->blog ? $app->blog->id : 0 );
    }
    return 0 unless $args->{ 'role' };
    my $role = MT->model( 'role' )->load( { name => $args->{ 'role' } } );
    if ( $role ) {
        require MT::Association;
        my $association = MT::Association->load( { author_id => $author->id,
                                                   blog_id => $blog_id,
                                                   role_id => $role->id,
                                                 } );
        if ( $association ) {
            return 1;
        }
    }
    return 0;
}

sub _hdlr_if_user_can {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    my $user = $app->user;
    return 0 unless defined $user;
    my $perm = $user->is_superuser;
    return 1 if $perm;
    my $permission = $args->{ permission };
    return 0 unless $permission;
    $permission = 'can_' . $permission;
    my $blog = $ctx->stash( 'blog' );
    my $blog_id = $args->{ blog_id };
    if ( defined( $blog_id ) && $blog_id =~ m/^\d+$/ ) {
        $perm = $user->permissions( $blog_id )->$permission;
    } elsif ( $blog ) {
        $perm = $user->permissions( $blog->id )->$permission;
    }
    return $perm;
}

sub _hdlr_entry_is_in_category {
    my ( $ctx, $args, $cond ) = @_;
    my $entry    = $ctx->stash('entry');
    my $category = $ctx->stash('category');
    return 0 unless defined $entry;
    return 0 unless defined $category;
    return 1 if $entry->is_in_category( $category );
    return 0;
}

sub _hdlr_if_module {
    my ( $ctx, $args, $cond ) = @_;
    my $module = $args->{ module };
    $module =~ s/\s+//g;
    if ( $module ) {
        die  "Invalid module name " . $module if $module =~ /[^\w:]/;
        eval "require $module";
        if (! $@ ) {
            return 1;
        }
    }
    return 0;
}

sub _hdlr_if_component {
    my ( $ctx, $args, $cond ) = @_;
    my $component = $args->{ component };
    $component = $args->{ plugin } unless $component;
    if ( $component ) {
        my $component = MT->component( $component );
        return 1 if $component;
    }
    return 0;
}

sub _hdlr_set_property_block {
    my ( $ctx, $args, $cond ) = @_;
    my $out = _hdlr_pass_tokens( @_ );
    $args->{ value } = $out;
    _hdlr_set_property( $ctx, $args, $cond );
    if ( $args->{ need_result } ) {
        return $out;
    }
    return '';
}

sub _hdlr_cache_property {
    my ( $ctx, $args, $cond ) = @_;
    my $value = _hdlr_get_property( $ctx, $args, $cond );
    return $value if $value;
    $args->{ need_result } = 1;
    return _hdlr_set_property_block( @_ );
}

sub _hdlr_if_property {
    my ( $ctx, $args, $cond ) = @_;
    my $name = $args->{ name };
    my $value = _hdlr_get_property( $ctx, $args, $cond );
    if (! $value ) {
        return 0;
    }
    $args->{ name } = $name;
    $ctx->{ __stash }{ vars }{ lc( $name ) } = $value;
    return MT::Template::Tags::Core::_hdlr_if( $ctx, $args, $cond );
}

sub _hdlr_if_regex_match {
    my ( $ctx, $args, $cond ) = @_;
    my $name = $args->{ name };
    my $str = $ctx->{ __stash }{ vars }{ lc( $name ) };
    my $patt = $args->{ regex };
    if ( $patt =~ m!^(/)(.+)\1([A-Za-z]+)?$! ) {
        $patt = $2;
        if ( my $opt = $3 ) {
            $opt =~ s/[ge]+//g;
            $patt = "(?$opt)" . $patt;
        }
        my $re = eval { qr/$patt/ };
        if ( defined $re ) {
            my $res;
            eval '$res = 1 if $str =~m/$re/;';
            if ( $@ ) {
                return $ctx->error( "Invalid regular expression: $@" );
            }
            return $res;
        }
    }
    return 0;
}

sub _filter_setproperty {
    my ( $text, $arg, $ctx ) = @_;
    my $name = $arg;
    my $blog_id;
    if ( ref( $arg ) eq 'ARRAY' ) {
        $name = @$arg[ 0 ];
        $blog_id = @$arg[ 1 ];
    }
    my $args;
    $args->{ name } = $name;
    $args->{ value } = $text;
    $args->{ blog_id } = $blog_id if $blog_id;
    return _hdlr_set_property( $ctx, $args );
}

sub _hdlr_set_property {
    my ( $ctx, $args, $cond ) = @_;
    my $name = $args->{ name };
    my $value = $args->{ value };
    my $blog_id = $args->{ blog_id } || 0;
    MT->request( "developer_property:${blog_id}:${name}", $value );
    my $property = MT->model( 'property' )->get_by_key( { blog_id => $blog_id, name => $name } );
    if ( ( $value ne $property->text ) || $args->{ update } || $args->{ force } ) {
        $property->text( $value );
        $property->start( time );
        $property->save or die $property->errstr;
    }
    return '';
}

sub _hdlr_get_property {
    my ( $ctx, $args, $cond ) = @_;
    my $name = $args->{ name };
    my $blog_id = $args->{ blog_id } || 0;
    my $value = MT->request( "developer_property:${blog_id}:${name}" );
    return $value if $value;
    my $property = MT->model( 'property' )->get_by_key( { blog_id => $blog_id, name => $name } );
    if ( $property ) {
        my $ttl = $args->{ ttl };
        if (! $ttl ) {
            $ttl = $args->{ expired };
        }
        if ( $ttl ) {
            my $start = $property->start;
            if ( ( time - $start ) > $ttl ) {
                return '';
            }
        }
    }
    if ( my $value = $property->text ) {
        MT->request( "developer_property:${blog_id}:${name}", $value );
        return $value;
    }
    return '';
}

sub _hdlr_delete_property {
    my ( $ctx, $args, $cond ) = @_;
    my $name = $args->{ name };
    my $blog_id = $args->{ blog_id } || 0;
    if ( $name ) {
        my $property = MT->model( 'property' )->load( { blog_id => $blog_id, name => $name } );
        $property->remove if defined( $property );
        MT->request( "developer_property:${blog_id}:${name}", undef );
    } else {
        if (! $blog_id ) {
            require Developer::Property;
            Developer::Property->remove_all;
        } else {
            my @props = MT->model( 'property' )->load( { blog_id => $blog_id } );
            for my $prop ( @props ) {
                $prop->remove or die $prop->errstr;
                MT->request( "developer_property:${blog_id}:" . $prop->name, undef );
            }
        }
    }
    return '';
}

sub _hdlr_file_info {
    my ( $ctx, $args, $cond ) = @_;
    my $terms;
    my @blog_ids = include_exclude_blogs( $ctx, $args );
    if ( $args->{ blog_id } ) {
        push( @blog_ids, $args->{ blog_id } );
    }
    if ( @blog_ids && ! $blog_ids[ 0 ] ) {
        @blog_ids = ();
    }
    if ( scalar @blog_ids ) {
        if ( ( scalar @blog_ids ) == 1 ) {
            if ( defined $blog_ids[ 0 ] ) {
                $terms->{ blog_id } = \@blog_ids;
            }
        } else {
            $terms->{ blog_id } = \@blog_ids;
        }
    }
    require MT::FileInfo;
    my $iter = MT::FileInfo->load_iter( $terms );
    my $last = MT::FileInfo->count( $terms );
    my $tokens = $ctx->stash( 'tokens' );
    my $builder = $ctx->stash( 'builder' );
    my $vars = $ctx->{ __stash }{ vars } ||= {};
    my $res = '';
    my $i = 1;
    my $glue = $args->{ glue };
    my $col = MT::FileInfo->column_names;
    while ( my $fi = $iter->() ) {
        $ctx->stash( 'fileinfo', $fi );
        for my $c ( @$col ) {
            $vars->{ $c } = $fi->$c;
        }
        local $vars->{ __counter__ } = $i;
        local $vars->{ __first__ } = 1 if $i == 1;
        local $vars->{ __last__ }  = 1 if $i == $last;
        local $vars->{ __odd__ }   = ( $i % 2 ) == 1;
        local $vars->{ __even__ }  = ( $i % 2 ) == 0;
        my $out = $builder->build( $ctx, $tokens, $cond );
        $res .= $out;
        $res .= $glue if $glue && $i != $last;
        $i++;
    }
    return $res;
}

sub _hdlr_send_mail {
    my ( $ctx, $args, $cond ) = @_;
    # <MTSendMail to="foo@example.com" subject="Subject" body="Body">
    # or
    # <MTSetVar name="options{To}" value="foo@example.com">
    # <MTSetVar name="Bcc[0]" value="bar@example.com">
    # <MTSetVar name="Bcc[1]" value="baz@alfasado.jp">
    # <MTSetVar name="options{Bcc}" value="$Bcc">
    # <MTSendMail subject="Subject" body="Body" options="$options">
    return '' if cancel_command();
    require MT::Mail;
    my $head;
    my $need_result = $args->{ need_result };
    my $from = $args->{ from } || MT->config( 'EmailAddressMain' );
    my $to = $args->{ to } || MT->config( 'EmailAddressMain' ) || '';
    if (! $to ) {
        if ( $need_result ) {
            return '0';
        }
        return '';
    }
    my $subject = $args->{ subject } || '';
    $head->{ To } = $to;
    if ( ref ( $to ) ne 'Array' ) {
        if ( $to =~ m/,/ ) {
            my @tos = split( /,/, $to );
            $head->{ To } = \@tos;
        }
    }
    $head->{ Subject } = $subject;
    my $body = $args->{ body } || '';
    my $options = $args->{ options };
    for my $key ( keys %$options ) {
        my $value = $options->{ $key };
        $head->{ $key } = $value;
    }
    force_background_task(
           sub { MT::Mail->send( $head, $body )
                or return ( 0, "The error occurred.", MT::Mail->errstr ); } );
    if ( $need_result ) {
        return 1;
    }
    return '';
}

sub _hdlr_copy_file_to {
    my ( $ctx, $args, $cond ) = @_;
    return '' if cancel_command();
    my $from = $args->{ from };
    my $to = $args->{ to };
    my $relative = MT->config( 'PathToRelative' );
    my $blog = $ctx->stash( 'blog' );
    if ( $relative && $blog ) {
        if (! $args->{ remove } ) {
            my $from_path = $blog->site_path;
            if ( ( $from =~ m!^/! ) || ( $from =~ m!^\\! ) ) {
                $from_path =~ s!/$!!;
                $from_path =~ s!\\$!!;
            }
            $from = File::Spec->catfile( $from_path, $from );
        }
        my $to_path = $blog->site_path;
        if ( ( $to =~ m!^/! ) || ( $to =~ m!^\\! ) ) {
            $to_path =~ s!/$!!;
            $to_path =~ s!\\$!!;
        }
        $to = File::Spec->catfile( $to_path, $to );
    }
    my $need_result = $args->{ need_result };
    my $component = MT->component( 'Developer' );
    if (! can_access_to( $to, $blog ) ) {
        my $message;
        if ( $args->{ remove } ) {
            $message = $component->translate( 'Cannot remove [_1].', $to );
        } else {
            $message = $component->translate( 'Cannot write to [_1].', $to );
        }
        if ( $need_result ) {
            $ctx->error( $message );
        } else {
            $args->{ message } = $message;
            _hdlr_log( $ctx, $args, $cond );
            return '';
        }
    }
    if ( $from && (! can_access_to( $from, $blog, 1 ) ) ) {
        my $message = $component->translate( 'Cannot access [_1].', $from );
        if ( $need_result ) {
            $ctx->error( $message );
        } else {
            $args->{ message } = $message;
            _hdlr_log( $ctx, $args, $cond );
            return '';
        }
    }
    my $res;
    if ( $args->{ move } ) {
        $res = move_to( $from, $to );
    } elsif ( $args->{ remove } ) {
        if (-d $to ) {
            $res = File::Path::rmtree( [ $to ] );
        } elsif ( -f $to ) {
            require MT::FileMgr;
            my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
            $res = $fmgr->delete( $to );
        }
    } else {
        $res = copy_to( $from, $to );
    }
    if ( $need_result ) {
        return $res;
    }
    return '';
}

sub _hdlr_remove_file {
    my ( $ctx, $args, $cond ) = @_;
    my $to = $args->{ path };
    if (! $to ) {
        $to = $args->{ file };
    }
    if (! $to ) {
        return '';
    }
    if (! -f $to ) {
        return '';
    }
    $args->{ to } = $to;
    $args->{ remove } = 1;
    return _hdlr_copy_file_to( $ctx, $args, $cond );
}

sub _hdlr_remove_directory {
    my ( $ctx, $args, $cond ) = @_;
    my $to = $args->{ path };
    if (! $to ) {
        $to = $args->{ directory };
    }
    if (! $to ) {
        return '';
    }
    if (! -d $to ) {
        return '';
    }
    $args->{ to } = $to;
    $args->{ remove } = 1;
    return _hdlr_copy_file_to( $ctx, $args, $cond );
}

sub _hdlr_read_from_file {
    my ( $ctx, $args, $cond ) = @_;
    return if cancel_command();
    my $component = MT->component( 'Developer' );
    my $from = $args->{ from };
    if (! $from ) {
        $from = $args->{ file };
    }
    my $relative = MT->config( 'PathToRelative' );
    my $blog = $ctx->stash( 'blog' );
    if ( $relative && $blog ) {
        my $from_path = $blog->site_path;
        if ( ( $from =~ m!^/! ) || ( $from =~ m!^\\! ) ) {
            $from_path =~ s!/$!!;
            $from_path =~ s!\\$!!;
        }
        $from = File::Spec->catfile( $from_path, $from );
    }
    return '' unless $from;
    my $need_result = $args->{ need_result };
    if ( $from && (! can_access_to( $from, $blog, 1 ) ) ) {
        my $message = $component->translate( 'Cannot access [_1].', $from );
        if ( $need_result ) {
            $ctx->error( $message );
        } else {
            $args->{ message } = $message;
            _hdlr_log( $ctx, $args, $cond );
            return '';
        }
    }
    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    if ( $fmgr->exists( $from ) ) {
        my $res = $fmgr->get_data( $from );
        return $res;
    }
    return '';
}

sub _hdlr_write_to_file {
    my ( $ctx, $args, $cond ) = @_;
    return if cancel_command();
    my $component = MT->component( 'Developer' );
    my $to = $args->{ to };
    if (! $to ) {
        $to = $args->{ file };
    }
    my $relative = MT->config( 'PathToRelative' );
    my $blog = $ctx->stash( 'blog' );
    if ( $relative && $blog ) {
        my $to_path = $blog->site_path;
        if ( ( $to =~ m!^/! ) || ( $to =~ m!^\\! ) ) {
            $to_path =~ s!/$!!;
            $to_path =~ s!\\$!!;
        }
        $to = File::Spec->catfile( $to_path, $to );
    }
    my $value = $args->{ value };
    if (! $value ) {
        $value = $args->{ content };
    }
    my $need_result = $args->{ need_result };
    if ( $to && (! can_access_to( $to, $blog ) ) ) {
        my $message = $component->translate( 'Cannot write to [_1].', $to );
        if ( $need_result ) {
            $ctx->error( $message );
        } else {
            $args->{ message } = $message;
            _hdlr_log( $ctx, $args, $cond );
            return '';
        }
    }
    my $res = 0;
    if ( $args->{ append } ) {
        my $glue = $args->{ glue };
        # $glue = eval $glue;
        if ( $glue eq '\n' ) {
            $glue = "\n";
        }
        if ( $glue eq '\r' ) {
            $glue = "\r";
        }
        if ( $glue eq '\t' ) {
            $glue = "\t";
        }
        if ( open( my $fh, '>>', $to ) ) {
            print $fh $value . $glue;
            close( $fh );
            $res = 1;
        }
    } else {
        require MT::FileMgr;
        my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
        $res = $fmgr->put_data( $value, $to );
    }
    if ( $need_result ) {
        return $res;
    }
    return '';
}

sub _hdlr_move_file_to {
    my ( $ctx, $args, $cond ) = @_;
    $args->{ move } = 1;
    return _hdlr_copy_file_to( $ctx, $args, $cond );
}

sub _hdlr_get_epoc {
    return time();
}

sub _hdlr_set_columns2vars {
    my ( $ctx, $args, $cond ) = @_;
    my $stash = $args->{ stash };
    if (! $stash ) {
        $stash = $args->{ object };
    }
    my $prefix = $args->{ prefix } || '';
    my $vars = $ctx->{ __stash }{ vars } ||= {};
    if (! $stash ) {
        if ( ( $ctx->{ __stash }{ vars }{ 'entry_archive' } ) ||
            ( $ctx->{ __stash }{ vars }{ 'page_archive' } ) ) {
            $stash = 'entry';
        }
    }
    if (! $stash ) {
        $stash = 'blog';
    }
    my $obj = $ctx->stash( $stash );
    if (! $obj ) {
        return '';
    }
    my $columns = $obj->column_names;
    for my $col ( @$columns ) {
        $ctx->{ __stash }{ vars }{ $prefix . $col } = $obj->$col;
    }
    if ( $obj->has_meta ) {
        my $model = $stash;
        if ( $obj->has_column( 'class' ) ) {
            $model = $obj->class;
        }
        my $blog_id;
        if ( $obj->has_column( 'blog_id' ) ) {
            $blog_id = $obj->blog_id;
        } else {
            $blog_id = $ctx->stash( 'blog_id' );
        }
        my @fields = MT->model( 'field' )->load( { blog_id => [ $blog_id, 0 ], obj_type => $model } );
        for my $field( @fields ) {
            my $basename = 'field.' . $field->basename;
            if ( $obj->has_column( $basename ) ) {
                $ctx->{ __stash }{ vars }{ $prefix . $basename } = $obj->$basename;
            }
        }
    }
    if ( $stash eq 'entry' ) {
        $ctx->{ __stash }{ vars }{ $prefix . 'permalink' } = $obj->permalink;
    }
    return '';
}

sub _hdlr_build {
    my ( $ctx, $args, $cond ) = @_;
    my $no_output = $args->{ no_output };
    my $res = $ctx->stash( 'builder' )->build( $ctx, $ctx->stash( 'tokens' ), $cond );
    if (! $no_output ) {
        return $res;
    }
    return '';
}

sub _hdlr_get_env {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    if ( ref ( $app ) eq 'MT::App::CMS' ) {
        my $env = $args->{ name };
        return $ENV{ $env };
    }
    return '';
}

sub _hdlr_get_cookie {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    if ( ref ( $app ) eq 'MT::App::CMS' ) {
        my $name = $args->{ name };
        return $app->cookie_val( $name );
    }
    return '';
}

sub _hdlr_get_header {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    if ( ref ( $app ) eq 'MT::App::CMS' ) {
        my $name = $args->{ name };
        return $app->get_header( $name );
    }
    return '';
}

sub _hdlr_vardump {
    my ( $ctx, $args, $cond ) = @_;
    my $name = $args->{ name };
    my $vars;
    if (! $name ) {
        $vars = $ctx->{ __stash }{ vars } ||= {};
    } else {
        $vars = $ctx->{ __stash }{ vars }{ $name } ||= {};
    }
    my $dump = Dumper $vars;
    $dump = encode_html( $dump );
    if (! $name ) {
        $dump = '<pre><code style="overflow:auto">' . $dump . '</code></pre>';
    } else {
        $dump = '<pre><code style="overflow:auto">' . $name . ' =&gt; ' . $dump . '</code></pre>';
    }
    return $dump;
}

sub _hdlr_cookiedump {
    my $vars = MT->instance->cookies;
    my $dump = Dumper $vars;
    $dump = encode_html( $dump );
    $dump = '<pre><code style="overflow:auto">' . $dump . '</code></pre>';
    return $dump;
}

sub _hdlr_querydump {
    my $var = MT->instance->query_string;
    return "<pre><code style=\"overflow:auto\">\n\$VAR1 = undef;\n</code></pre>" if ! $var;
    my @vars = split( /;/, $var );
    my $params;
    for my $query ( @vars ) {
        my ( $key, $value ) = split( /=/, $query );
        $params->{ $key } = $value;
    }
    my $dump = Dumper $params;
    $dump = encode_html( $dump );
    $dump = '<pre><code style="overflow:auto">' . $dump . '</code></pre>';
    return $dump;
}

sub _hdlr_envdump {
    my $params;
    for my $key ( keys %ENV ) {
        $params->{ $key } = $ENV{ $key };
    }
    my $dump = Dumper $params;
    $dump = encode_html( $dump );
    $dump = '<pre><code style="overflow:auto">' . $dump . '</code></pre>';
    return $dump;
}

# <MTCountGroupBy model="entry" column="keywords" sort_by="count" sort_order="descend" glue="<br />" not_null="1">
# (<$mt:var name="__group_count__"$>)<$mt:var name="__group_value__"$>
# (<$mt:CountGroupCount$>)<$mt:CountGroupValue escape="html"$>
# </MTCountGroupBy>

sub _hdlr_count_group_by {
    my ( $ctx, $args, $cond ) = @_;
    my $model = $args->{ model } || 'entry';
    $model = lc( $model );
    if ( $model eq 'author' ) {
        return '';
    }
    my $column = $args->{ column } || 'title';
    my $terms;
    my @blog_ids = include_exclude_blogs( $ctx, $args );
    if ( $args->{ blog_id } ) {
        push( @blog_ids, $args->{ blog_id } );
    }
    if ( @blog_ids && ! $blog_ids[ 0 ] ) {
        @blog_ids = ();
    }
    if ( scalar @blog_ids ) {
        if ( ( scalar @blog_ids ) == 1 ) {
            if ( defined $blog_ids[ 0 ] ) {
                $terms->{ blog_id } = \@blog_ids;
            }
        } else {
            $terms->{ blog_id } = \@blog_ids;
        }
    }
    if ( MT->model( $model )->has_column( 'status' ) ) {
        $terms->{ status } = 2;
    }
    my $sort = $args->{ sort_by } || 'count';
    my $direction = $args->{ sort_order } || 'descend';
    my $limit = $args->{ lastn };
    my $not_null = $args->{ not_null };
    if ( $not_null ) {
        $terms->{ $column } = { not => '' };
    }
    my $iter = MT->model( $model )->count_group_by( $terms, { group => [ $column ] } );
    my $result;
    my $last = 0;
    while ( my ( $count, $value ) = $iter->() ) {
        push ( @$result, { count => $count, value => $value } );
        $last++;
        if ( $limit && ( $last == $limit ) ) {
            last;
        }
    }
    if (! $result ) {
        return '';
    }
    if ( $direction ne 'descend' ) {
        @$result = sort { $a->{ $sort } <=> $b->{ $sort } } @$result;
    } else {
        @$result = sort { $b->{ $sort } <=> $a->{ $sort } } @$result;
    }
    my $tokens = $ctx->stash( 'tokens' );
    my $builder = $ctx->stash( 'builder' );
    my $vars = $ctx->{ __stash }{ vars } ||= {};
    my $res = '';
    my $i = 1;
    my $glue = $args->{ glue };
    for my $value ( @$result ) {
        my $text = utf8_on( $value->{ value } );
        $ctx->stash( 'group_count', $value->{ count } );
        $ctx->stash( 'group_value', $text );
        local $vars->{ __group_count__ } = $value->{ count };
        local $vars->{ __group_value__ } = $text;
        local $vars->{ __counter__ } = $i;
        local $vars->{ __first__ } = 1 if $i == 1;
        local $vars->{ __last__ }  = 1 if $i == $last;
        local $vars->{ __odd__ }   = ( $i % 2 ) == 1;
        local $vars->{ __even__ }  = ( $i % 2 ) == 0;
        my $out = $builder->build( $ctx, $tokens, $cond );
        $res .= $out;
        $res .= $glue if $glue && $i != $last;
        $i++;
    }
    return $res;
}

sub _hdlr_query2log {
    my ( $ctx, $args, $cond ) = @_;
    my $message = $args->{ message } || '';
    if ( $message ) {
        $message .= ' : ';
    }
    my $app = MT->instance;
    if ( ( ref $app ) !~ /^MT::App::/ ) {
        return '';
    }
    my $q = $app->query_string;
    if ( $args->{ url } ) {
        my $sep = '';
        if ( $q ) {
            $sep = '?';
        }
        $q = $app->base . $app->path . $app->script . $sep . $q;
    }
    $message .= $q;
    $args->{ message } = $message;
    _hdlr_log( $ctx, $args, $cond );
    my $print = $args->{ 'print' };
    if (! $print ) {
        $print = $args->{ 'echo' };
    }
    if ( $print ) {
        return $message;
    }
    return '';
}

sub _hdlr_log {
    my ( $ctx, $args, $cond ) = @_;
    my $message = $args->{ message } || '';
    my $lebel = $args->{ level } || MT::Log::DEBUG();
    my $catgory = $args->{ catgory } || 'developer';
    my $blog_id = $args->{ blog_id };
    my $log = {
                message => $message,
                catgory => $catgory,
                level => $lebel,
    };
    my $app = MT->instance;
    if ( ref( $app ) =~ /^MT::App::/ ) {
        if (! $blog_id ) {
            if ( $app->blog ) {
                $blog_id = $app->blog->id;
            }
        }
        $log->{ ip } = $app->remote_ip;
        if ( $app->user ) {
            $log->{ author_id } = $app->user->id;
        }
    }
    if ( $blog_id ) {
        $log->{ blog_id } = $blog_id;
    }
    $app->log( $log );
    my $print = $args->{ 'print' };
    if (! $print ) {
        $print = $args->{ 'echo' };
    }
    if ( $print ) {
        return $message;
    }
    return '';
}

sub _hdlr_speedmeter {
    my ( $ctx, $args, $cond ) = @_;
    my $component = MT->component( 'Developer' );
    my $scope = lc( MT->config( 'SpeedMeterDebugScope' ) );
    if ( (! $scope ) || ( $scope && $scope eq 'none' ) ) {
        return $ctx->stash( 'builder' )->build( $ctx, $ctx->stash( 'tokens' ), $cond );
    }
    my $name = $args->{ name };
    my $start = Time::HiRes::time();
    my $value = $ctx->stash( 'builder' )->build( $ctx, $ctx->stash( 'tokens' ), $cond );
    my $end = Time::HiRes::time();
    my $time = $end - $start;
    my $message = $component->translate( 'The template for [_1] have been build.', "'$name'" );
    $message .= $component->translate( 'Publish time: [_1].', $time );
    if ( $scope eq 'log' ) {
        MT->log( $message );
    } elsif ( $scope eq 'screen' ) {
        my $prefix = $args->{ prefix } || '';
        my $suffix = $args->{ suffix } || '';
        $value .= $prefix . $message . $suffix;
    }
    return $value;
}

sub _hdlr_setcookie {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    if ( ( ref $app ) !~ /^MT::App::/ ) {
        return '';
    }
    my $reload = $args->{ reload };
    my $name = $args->{ name };
    my $cookie_val = $app->cookie_val( $name );
    my $value = $args->{ value };
    my $path = $args->{ path } || '/';
    my $domain = $args->{ domain };
    my $expires = $args->{ expires };
    my $secure = $args->{ secure };
    my %kookee = (
        -name  => $name,
        -value => $value,
        -path  => $path,
    );
    $kookee{ -domain } = $domain if $domain;
    $kookee{ -expires } = $expires if $expires;
    $kookee{ -secure } = $secure if $secure;
    if ( $app->bake_cookie( %kookee ) ) {
        if ( $reload ) {
            if ( $cookie_val ne $value ) {
                my $return_url = $app->base . $app->uri;
                if ( my $query_string = $app->query_string ) {
                    $return_url .= '?' . $query_string;
                }
                $app->redirect( $return_url );
            }
        }
    }
}

sub _hdlr_clearcookie {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    if ( ( ref $app ) !~ /^MT::App::/ ) {
        return '';
    }
    my $reload = $args->{ reload };
    my $name = $args->{ name };
    my $cookie_val = $app->cookie_val( $name );
    my $value = '';
    my $path = $args->{ path } || '/';
    my $domain = $args->{ domain };
    my $expires = '-1y';
    my $secure = $args->{ secure };
    my %kookee = (
        -name  => $name,
        -value => $value,
        -path  => $path,
        -expires => $expires,
    );
    $kookee{ -domain } = $domain if $domain;
    $kookee{ -secure } = $secure if $secure;
    if ( $app->bake_cookie( %kookee ) ) {
        if ( $reload ) {
            if ( $cookie_val ne $value ) {
                my $return_url = $app->base . $app->uri;
                if ( my $query_string = $app->query_string ) {
                    $return_url .= '?' . $query_string;
                }
                $app->redirect( $return_url );
            }
        }
    }
}

sub _hdlr_if_cookie {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    if ( (ref $app) !~ /^MT::App::/ ) {
        return 0;
    }
    my $name = $args->{ name };
    my $cookie = $app->cookie_val( $name );
    if (! $cookie ) {
        return 0;
    }
    $args->{ name } = $name;
    $ctx->{ __stash }{ vars }{ lc( $name ) } = $cookie;
    return MT::Template::Tags::Core::_hdlr_if( $ctx, $args, $cond );
}

sub _hdlr_if_validate_magic {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    if ( (ref $app) !~ /^MT::App::/ ) {
        return 0;
    }
    if ( my $magic_token = $app->param( 'magic_token' ) ) {
        return 1 if ( $app->current_magic eq $magic_token );
    }
    return 0;
}

sub _hdlr_magic_token {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    if ( (ref $app) !~ /^MT::App::/ ) {
        return '';
    }
    if (! $app->user ) {
        return '';
    }
    return $app->current_magic();
}

sub _hdlr_if_header {
    my ( $ctx, $args, $cond ) = @_;
    my $header = _hdlr_get_header( $ctx, $args, $cond );
    my $name = $args->{ name };
    $args->{ name } = $name;
    $ctx->{ __stash }{ vars }{ lc( $name ) } = $header;
    return MT::Template::Tags::Core::_hdlr_if( $ctx, $args, $cond );
}

sub _hdlr_count_group_value {
    my ( $ctx, $args, $cond ) = @_;
    return $ctx->stash( 'group_value' );
}

sub _hdlr_count_group_count {
    my ( $ctx, $args, $cond ) = @_;
    return $ctx->stash( 'group_count' );
}

sub _hdlr_html_compressor {
    my ( $ctx, $args, $cond ) = @_;
    my $out = _hdlr_pass_tokens( @_ );
    $out = MT->instance->translate_templatized( $out );
    require HTML::Packer;
    my $packer = HTML::Packer->init();
    $out = $packer->minify( \$out, $args );
    return $out;
}

sub _hdlr_css_compressor {
    my ( $ctx, $args, $cond ) = @_;
    my $out = _hdlr_pass_tokens( @_ );
    $out = MT->instance->translate_templatized( $out );
    my $archive_file = $ctx->stash( 'current_archive_file' );
    $out =~ s/\r\n?/\n/g;
    if ( $args->{ flatten_css_imports } && $archive_file ) {
        require File::Spec;
        require File::Basename;
        require MT::FileMgr;
        my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
        my $dir = File::Basename::dirname( $archive_file );
        my $app = MT->instance;
        my @imports;
        my @lines = split( /\n/, $out );
        for my $line ( @lines ) {
            if ( $line =~ /^\@import/ ) {
                push( @imports, $line );
            }
        }
        my ( $document_root, $base_root, $base);
        if ( scalar ( @imports ) ) {
            my $blog = $ctx->stash( 'blog' );
            if ( (ref ( $app ) =~ /^MT::App::/ ) && !$blog )  {
                $document_root = $app->document_root;
                $base = $app->base;
            } elsif ( $blog ) {
                $base = $blog->site_url;
                if ( $base =~ m!(^https{0,1}://.*?)(/.*)/$! ) {
                    $base = $1;
                    $document_root = $blog->site_path;
                    if ( $^O eq 'MSWin32' ) {
                        $document_root =~ s!\\!/!g;
                    }
                    my $end = quotemeta( $2 );
                    $document_root =~ s/$end$//;
                    if ( $^O eq 'MSWin32' ) {
                        $document_root =~ s!/!\\!g;
                    }
                }
            }
            $base_root = quotemeta( $base );
        }
        for my $import ( @imports ) {
            if ( $import =~ /['"](.*?)['"]/ ) {
                my $match = $1;
                my $in;
                if (( ! $app->config( 'AllowIncludeParentDir' ))
                        && $match =~ m/\.\./ ) {
                } else {
                    if ( ( $match !~ /^http/ ) && ( $match !~ m!^/! ) ) {
                        $in = File::Spec->rel2abs( $1, $dir );
                    } elsif ( $match =~ m/^\// ) {
                        $in = $document_root . $match;
                    } elsif ( $match =~ /^http/ ) {
                        if ( $match =~ /^$base_root/ ) {
                            $in = $match;
                            $in =~ s/^$base_root/$document_root/;
                        }
                    }
                    if ( $^O eq 'MSWin32' ) {
                        $in =~ s!/!\\!g;
                    }
                    if ( $in && $fmgr->exists( $in ) ) {
                        my $css = $fmgr->get_data( $in );
                        $import = quotemeta( $import );
                        $out =~ s/$import/$css/;
                    }
                }
            }
        }
    }
    require CSS::Minifier;
    $out = CSS::Minifier::minify( input => $out );
    if ( $args->{ flatten_css_imports } ) {
        $out =~ s/\n/ /g;
    }
    return $out;
}

sub _hdlr_js_compressor {
    my ( $ctx, $args, $cond ) = @_;
    my $out = _hdlr_pass_tokens( @_ );
    $out = MT->instance->translate_templatized( $out );
    require JavaScript::Minifier;
    $out = JavaScript::Minifier::minify( input => $out );
    return $out;
}

sub _hdlr_translate {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    my $lang = MT->config( 'DefaultLanguage' );
    my $phrase = $args->{ phrase };
    my $params = $args->{ params };
    my $debug = $args->{ debug };
    if ( ref( $app ) =~ /^MT::App::/ ) {
        my $cookie_name = $args->{ use_cookie };
        if ( $cookie_name ) {
            $lang = $app->cookie_val( $cookie_name );
        } else {
            if ( my $user = $app->user ) {
                $lang = $user->preferred_language;
            } else {
                $lang = $app->get_header( 'Accept-Language' );
            }
        }
    }
    $lang = $app->get_header( 'Accept-Language' );
    $lang =~ s/\-/_/g;
    if ( $lang && $lang =~ m/^j[a|p]/ ) {
        $lang = 'ja';
    }
    if ( $debug ) {
        return $lang;
    }
    my $component = $args->{ component } || MT->config( 'TranslateComponent' );
    if ( $component ) {
        $component = MT->component( $component );
    } else {
        $component = MT->component( 'Core' );
    }
    return translate_phrase( $component, $lang, $phrase, $params );
}

sub _hdlr_if_language {
    my ( $ctx, $args, $cond ) = @_;
    my $language = $args->{ language };
    $args->{ debug } = 1;
    my $lang = _hdlr_translate( $ctx, $args, $cond );
    if ( $lang eq $language ) {
        return 1;
    }
    return 0;
}

sub _hdlr_pass_tokens {
    my ( $ctx, $args, $cond ) = @_;
    $ctx->stash( 'builder' )->build( $ctx, $ctx->stash( 'tokens' ), $cond );
}

sub _hdlr_asset_thumbnail_file {
    my ( $ctx, $args ) = @_;
    my $asset = $ctx->stash( 'asset' )
        or return $ctx->_no_asset_error();
    return '' unless $asset->has_thumbnail;
    my %arg;
    foreach ( keys %$args ) {
        $arg{ $_ } = $args->{ $_ };
    }
    $arg{ Width }  = $args->{ width }  if $args->{ width };
    $arg{ Height } = $args->{ height } if $args->{ height };
    $arg{ Scale }  = $args->{ scale }  if $args->{ scale };
    $arg{ Square } = $args->{ square } if $args->{ square };
    my ( $file, $w, $h ) = $asset->thumbnail_file( %arg );
    return $file || '';
}

sub _filter_convert2base64 {
    my $src = shift;
    require MT::FileMgr;
    my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
    if ( $fmgr->exists( $src ) ) {
        require MT::Session;
        require Digest::MD5;
        my $id = 'base64:' . Digest::MD5::md5_hex( $src );
        my $cache = MT::Session->get_by_key( { id => $id, kind => 'B6' } );
        if ( my $data = $cache->data ) {
            my $update = ( stat( $src ) )[9];
            if ( $cache->start < $update ) {
            } else {
                return $data;
            }
        }
        my $data = $fmgr->get_data( $src, 'upload' );
        my $out = encode_base64( $data, '' );
        $cache->data( $out );
        $cache->start( time );
        $cache->save or die $cache->errstr;
        return $out;
    }
    return '';
}

sub _hdlr_set_context {
    my ( $ctx, $args, $cond ) = @_;
    require MT::Blog;
    my $blog = $ctx->stash( 'blog' );
    my $orig_blog = $blog;
    my $orig_category = $ctx->stash( 'category' );
    my $orig_entry = $ctx->stash( 'entry' );
    my $orig_author = $ctx->stash( 'author' );
    my $orig_current_timestamp = $ctx->{ current_timestamp };
    my $orig_current_timestamp_end = $ctx->{ current_timestamp_end };
    my $tokens = $ctx->stash( 'tokens' );
    my $builder = $ctx->stash( 'builder' );
    require MT::Template::Context;
    $ctx = MT::Template::Context->new;
    if ( my $blog_id = $args->{ blog_id } ) {
        $blog = MT::Blog->load( $blog_id );
        $ctx->stash( 'blog', $blog );
        $ctx->stash( 'blog_id', $blog->id );
        $args->{ blog_id } = $blog->id;
    }
    my ( %blog_terms, %blog_args );
    $ctx->set_blog_load_context( $args, \%blog_terms, \%blog_args )
        or return $ctx->error( $ctx->errstr );
    if ( my $author_id = $args->{ author_id } ) {
        require MT::Author;
        my $author = MT::Author->load( $author_id );
        $ctx->stash( 'author', $author );
    }
    if ( my $author_name = $args->{ author } ) {
        require MT::Author;
        my $author = MT::Author->load( { name => $author_name } );
        $ctx->stash( 'author', $author );
    }
    if ( my $entry_id = $args->{ entry_id } ) {
        require MT::Entry;
        my $entry = MT::Entry->load( $entry_id );
        $ctx->stash( 'entry', $entry );
        if ( $blog->id != $entry->blog_id ) {
            $ctx->stash( 'blog', $entry->blog );
            $ctx->stash( 'blog_id', $entry->blog->id );
        }
    }
    if ( my $category_id = $args->{ category_id } ) {
        require MT::Category;
        my $category = MT::Category->load( $category_id );
        $ctx->stash( 'category', $category );
        $ctx->stash( 'archive_category', $category );
        if ( $blog->id != $category->blog_id ) {
            $ctx->stash( 'blog', MT::Blog->load( $category->blog_id ) );
            $ctx->stash( 'blog_id', $category->blog_id );
        }
    }
    if ( my $category_arg = $args->{ category } ) {
        my @cats = $ctx->cat_path_to_category( $category_arg,
            [ \%blog_terms, \%blog_args ], 'category' );
        if ( @cats ) {
            my $category = $cats[ 0 ];
            $ctx->stash( 'category', $category );
            $ctx->stash( 'archive_category', $category );
            if ( $blog->id != $category->blog_id ) {
                $ctx->stash( 'blog', MT::Blog->load( $category->blog_id ) );
                $ctx->stash( 'blog_id', $category->blog_id );
            }
        }
    }
    if ( my $category_arg = $args->{ folder } ) {
        my @cats = $ctx->cat_path_to_category( $category_arg,
            [ \%blog_terms, \%blog_args ], 'folder' );
        if ( @cats ) {
            my $category = $cats[ 0 ];
            $ctx->stash( 'category', $category );
            $ctx->stash( 'archive_category', $category );
            if ( $blog->id != $category->blog_id ) {
                $ctx->stash( 'blog', MT::Blog->load( $category->blog_id ) );
                $ctx->stash( 'blog_id', $category->blog_id );
            }
        }
    }
    if ( my $current_timestamp = $args->{ current_timestamp } ) {
        $ctx->{ current_timestamp }= $current_timestamp;
    }
    if ( my $current_timestamp_end = $args->{ current_timestamp_end } ) {
        $ctx->{ current_timestamp_end }= $current_timestamp_end;
    }
    my $html = $builder->build( $ctx, $tokens, $cond );
    $ctx->stash( 'blog', $orig_blog );
    $ctx->stash( 'category', $orig_category );
    $ctx->stash( 'archive_category', $orig_category );
    $ctx->stash( 'entry', $orig_entry );
    $ctx->stash( 'author', $orig_author );
    $ctx->{ current_timestamp } = $orig_current_timestamp;
    $ctx->{ current_timestamp_end } = $orig_current_timestamp_end;
    return $html;
}

sub _hdlr_clear_context {
    my ( $ctx, $args, $cond ) = @_;
    my $tokens = $ctx->stash( 'tokens' );
    my $builder = $ctx->stash( 'builder' );
    require MT::Template::Context;
    $ctx = MT::Template::Context->new;
    my $html = $builder->build( $ctx, $tokens, $cond );
    return $html;
}

sub _hdlr_build_link {
    my ( $ctx, $args, $cond ) = @_;
    my ( $blog, $blog_id );
    if ( defined( $blog_id = $args->{ blog_id } ) ) {
        require MT::Blog;
        $blog = MT::Blog->load( $blog_id );
        $ctx->stash( 'blog', $blog );
    }
    $blog = $ctx->stash( 'blog' );
    if ( $blog ) {
        $blog_id = $blog->id;
        $ctx->stash( 'blog_id', $blog_id );
    }
    my $url;
    if ( defined( my $tag = $args->{ tag } ) ) {
        $tag =~ s/^<//;
        $tag =~ s/>$//;
        $tag =~ s/^MT:?//i;
        require Storable;
        my $local_args = Storable::dclone( $args );
        if ( defined( my $modifier = $args->{ tagmodifier } ) ) {
            $modifier =~ s/\\//g;
            my @modifiers = split( /\s/, $modifier );
            for my $m ( @modifiers ) {
                my @lr = split( /=/, $m );
                my $l = $lr[ 0 ];
                my $r = $lr[ 1 ];
                $r =~ s/^"(.*?)"$/$1/;
                $local_args->{ $l } = $r;
            }
        }
        $url = $ctx->tag( $tag, $local_args, $cond );
    } else {
        $url = $args->{ url };
    }
    my $label;
    if ( defined( my $tag = $args->{ labeltag } ) ) {
        $tag =~ s/^<//;
        $tag =~ s/>$//;
        $tag =~ s/^MT:?//i;
        require Storable;
        my $local_args = Storable::dclone( $args );
        if ( defined( my $modifier = $args->{ labelmodifier } ) ) {
            $modifier =~ s/\\//g;
            my @modifiers = split( /\s/, $modifier );
            for my $m ( @modifiers ) {
                my @lr = split( /=/, $m );
                my $l = $lr[ 0 ];
                my $r = $lr[ 1 ];
                $r =~ s/^"(.*?)"$/$1/;
                $local_args->{ $l } = $r;
            }
        }
        $label = $ctx->tag( $tag, $local_args, $cond );
    } else {
        $label = $args->{ label };
    }
    if ( defined( $args->{ iftheurlfound } ) ) {
        if (! defined( $args->{ mtml } ) ) {
            $args->{ need_path } = 1;
            my ( $file, $blog ) = _hdlr_if_the_url_found( $ctx, $args, $cond );
            if (! $file ) {
                if ( ( defined( $args-> { target_outlink } ) )
                    || ( MT->config( 'ForceTargetOutLink' ) ) ) {
                    if (! MT->request( 'theURLExists:' . $url ) ) {
                        my $response = _get_response_header( $url );
                        if ( $response->is_success ) {
                            MT->request( 'theURLExists:' . $url, 1 );
                        } else {
                            return '';
                        }
                    }
                }
            }
        }
    }
    if (! $url ) {
        return '';
    }
    if ( defined( $args->{ html } ) ) {
        return $args->{ html };
    }
    my $link = '<a href="' . $url . '"';
    if ( defined( $args->{ attribute } ) ) {
        my $attribute = $args->{ attribute };
        $link .= " ${attribute}";
    }
    $link .= ">${label}</a>";
    if ( defined( $args->{ prefix } ) ) {
        $link = $args->{ prefix } . $link;
    }
    if ( defined( $args->{ postfix } ) ) {
        $link .= $args->{ postfix };
    }
    if ( defined( $args->{ iftheurlfound } ) ) {
        if ( defined( $args->{ mtml } ) ) {
            # <MTBuildLink url="http://www.example.com/"
            # html='<li><a href="http://www.example.com/" target="_blank">Movable Type</a></li>'
            # IfTheUrlFound="1" blog_id="1">
            my $mtml = '<mt:BuildLink url="' . $url . '" html=\'' . $link . '\' iftheurlfound="1"';
            if ( $blog_id ) {
                $mtml .= ' blog_id="' . $blog_id . '"';
            }
            $mtml .= '>';
            return $mtml;
        }
    }
    return $link;
}

sub _hdlr_if_the_url_found {
    my ( $ctx, $args, $cond ) = @_;
    my ( $blog, $blog_id );
    if ( defined( $blog_id = $args->{ blog_id } ) ) {
        require MT::Blog;
        $blog = MT::Blog->load( $blog_id );
        $ctx->stash( 'blog', $blog );
    }
    $blog = $ctx->stash( 'blog' );
    if ( $blog ) {
        $blog_id = $blog->id;
        $ctx->stash( 'blog_id', $blog_id );
    }
    my $url;
    if ( defined( my $tag = $args->{ tag } ) ) {
        $tag =~ s/^<//;
        $tag =~ s/>$//;
        $tag =~ s/^MT:?//i;
        require Storable;
        my $local_args = Storable::dclone( $args );
        if ( defined( my $modifier = $args->{ tagmodifier } ) ) {
            $modifier =~ s/\\//g;
            my @modifiers = split( /\s/, $modifier );
            for my $m ( @modifiers ) {
                my @lr = split( /=/, $m );
                my $l = $lr[ 0 ];
                my $r = $lr[ 1 ];
                $r =~ s/^"(.*?)"$/$1/;
                $local_args->{ $l } = $r;
            }
        }
        $url = $ctx->tag( $tag, $local_args, $cond );
    } else {
        $url = $args->{ url };
    }
    my $app = MT->instance;
    my $base = $app->base;
    if ( $blog ) {
        $base = $blog->site_url;
        $base =~ s!/$!!;
    }
    my $base_url = quotemeta( $base );
    if ( $url =~ /^$base_url/ ) {
        # File Check.
        my $base_path = $app->document_root();
        if ( $blog ) {
            $base_path = $blog->site_path;
            $base_path =~ s!/$!!;
            $base_path =~ s!\\$!!;
        }
        my $file = $url;
        $file =~ s/^$base_url/$base_path/;
        my $index = $app->config( 'IndexBasename' );
        $index = 'index' if (! $index );
        if ( ( $file =~ /\/$/ ) || ( $file =~ /\\$/ ) ) {
            my $file_extension = 'html';
            if ( ( $blog ) && ( $blog->file_extension ) ) {
                $file_extension = $blog->file_extension;
            }
            $file .= $index . '.' . $file_extension;
        }
        require MT::FileMgr;
        my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
        if ( $fmgr->exists( $file ) ) {
            if ( $args->{ need_path } ) {
                return ( $file, $blog );
            }
            return 1;
        } else {
            if ( $args->{ target_dynamic }) {
                require MT::FileInfo;
                my $data = MT::FileInfo->load( { file_path => $file, virtual => 1 } );
                if ( $data ) {
                    if ( $args->{ need_path } ) {
                        return ( $file, $blog );
                    }
                    return 1;
                }
            }
            if ( $args->{ need_path } ) {
                return undef;
            }
            return 0;
        }
    } else {
        if ( $args->{ need_path } ) {
            return undef;
        }
        if ( (! $args-> { target_outlink } ) 
            && (! MT->config( 'ForceTargetOutLink' ) ) ) {
            return 0;
        }
        if ( MT->request( 'theURLExists:' . $url ) ) {
            return 1;
        }
        my $response = _get_response_header( $url );
        if ( $response->is_success ) {
            MT->request( 'theURLExists:' . $url, 1 );
            return 1;
        } else {
            return 0;
        }
    }
    if ( $args->{ need_path } ) {
        return undef;
    }
    return 1;
}

sub _hdlr_get_url_mtime {
    my ( $ctx, $args, $cond ) = @_;
    $args->{ need_path } = 1;
    my ( $file, $blog ) = _hdlr_if_the_url_found( $ctx, $args, $cond );
    my $mtime;
    if ( $file && ( -f $file ) ) {
        $mtime = ( stat( $file ) )[ 9 ];
    } else {
        if ( (! $args-> { target_outlink } )
            && (! MT->config( 'ForceTargetOutLink' ) ) ) {
            return 0;
        }
        my $url = $args->{ url };
        my $response = _get_response_header( $url );
        if ( $response->is_success ) {
            MT->request( 'theURLExists:' . $url, 1 );
            $mtime = $response->{ _headers }->{ 'last-modified' };
            require HTTP::Date;
            $mtime = HTTP::Date::str2time( $mtime );
        } else {
            return 0;
        }
    }
    if ( $mtime ) {
        $mtime = epoch2ts( $blog, $mtime );
        $args->{ ts } = $mtime;
        return $ctx->build_date( $args );
    }
    return 0;
}

sub _filter_outiftheurlfound {
    my ( $text, $url, $ctx ) = @_;
    if ( $url !~ m!^https{0,1}://! ) {
        if ( $text =~ m!"(https{0,1}://.*?)"! ) {
            $url = $1;
        } elsif ( $text =~ m!'(https{0,1}://.*?)'! ) {
            $url = $1;
        }
        return '' unless $url;
    }
    my $args;
    $args->{ url } = $url;
    $args->{ need_path } = 1;
    $args->{ target_dynamic } = 1;
    my ( $file, $blog ) = _hdlr_if_the_url_found( $ctx, $args );
    return $text if $file;
    if (! $file ) {
        if ( MT->config( 'ForceTargetOutLink' ) ) {
            my $response = _get_response_header( $url );
            if ( $response->is_success ) {
                return $text;
            }
        }
    }
    return '';
}

sub _get_response_header {
    my $url = shift;
    my $app = MT->instance;
    require LWP::UserAgent;
    my $remote_ip = $app->remote_ip;
    my $agent = "Mozilla/5.0 (Movable Type Developer plugin X_FORWARDED_FOR:$remote_ip)";
    my $ua = LWP::UserAgent->new( agent => $agent );
    my $response = $ua->head( $url );
    return $response;
}

sub _hdlr_rebuild {
    my ( $ctx, $args, $cond ) = @_;
    my $app = MT->instance;
    if ( ref ( $app ) eq 'MT::App::CMS' ) {
        my $mode = $app->mode;
        if ( $mode && ( $mode =~ /preview/ ) ) {
            return;
        }
    }
    my $url = $args->{ url };
    my $blog_id = $args->{ blog_id };
    my $blog = $ctx->stash( 'blog' );
    my $need_result = $args->{ need_result };
    if ( $blog_id ) {
        require MT::Blog;
        $blog = MT::Blog->load( $blog_id );
        $ctx->stash( 'blog', $blog );
        $ctx->stash( 'blog_id', $blog_id );
    }
    if (! $blog ) {
        if ( ref( $app ) =~ /^MT::App::/ ) {
            $blog = $app->blog;
        }
        if (! $blog ) {
            return $ctx->error( MT->translate( 'No [_1] could be found.', 'Blog' ) );
        }
    }
    $blog_id = $blog->id;
    if ( $url ) {
        if ( $url =~ m!^https{0,1}://! ) {
            my $blog_url = $blog->site_url;
            $blog_url =~ s!/$!!;
            $blog_url =~ s!(^https{0,1}://.*?)/.*$!$1!;
            my $search = quotemeta( $blog_url );
            $url =~ s/^$search//;
        }
        if ( $url =~ m!/$! ) {
            my $index = MT->config( 'IndexBasename' ) . '.' . $blog->file_extension;
            $url .= $index;
        }
        if (! $args->{ force } ) {
            my $key = 'rebuildtrigger-rebuild-url:' . $blog_id . ':' . $url;
            if ( MT->request( $key ) ) {
                return '';
            }
            MT->request( $key, 1 );
        }
        require MT::FileInfo;
        my $fi = MT::FileInfo->load( { blog_id => $blog_id,
                                       url => $url } );
        if (! $fi ) {
            return '';
        }
        require MT::WeblogPublisher;
        my $pub = MT::WeblogPublisher->new;
        $pub->rebuild_from_fileinfo( $fi ) || die $pub->errstr;
        return 1 if $need_result;
        return '';
    }
    $args->{ need_result } = 1;
    if ( _hdlr_rebuild_blog( @_ ) || _hdlr_rebuild_indexbyid( @_ ) ) {
        return 1 if $need_result;
    }
    return '';
}

sub _hdlr_rebuild_blog {
    my ( $ctx, $args, $cond ) = @_;
    my $need_result = $args->{ need_result };
    my $blog_id = $args->{ blog_id };
    $blog_id = $args->{ id } if (! $blog_id );
    $blog_id = $args->{ blog_ids } if (! $blog_id );
    my $archivetype = $args->{ ArchiveType };
    $archivetype = $args->{ archivetype } if (! $archivetype );
    $archivetype = $args->{ archive_type } if (! $archivetype );
    $archivetype = '' if (! $archivetype );
    my @ats;
    if ( $archivetype ) {
        @ats = split( /\,/, $archivetype );
        @ats = map { $_ =~ s/\s//g; $_; } @ats;
    }
    my @blog_ids = split( /\,/, $blog_id );
    @blog_ids = map { $_ =~ s/\s//g; $_; } @blog_ids;
    return '' unless @blog_ids;
    my $do = rebuild_blogs( \@blog_ids, \@ats );
    if ( $need_result ) {
        return $do;
    }
    return '';
}

sub _hdlr_rebuild_indexbyid {
    my ( $ctx, $args, $cond ) = @_;
    my $need_result = $args->{ need_result };
    my $template_id = $args->{ template_id };
    $template_id = $args->{ id } if (! $template_id );
    $template_id = $args->{ template_ids } if (! $template_id );
    return '' unless $template_id;
    my @template_ids = split( /\,/, $template_id );
    @template_ids = map { $_ =~ s/\s//g; $_; } @template_ids;
    my $do = rebuild_templates( \@template_ids, $args->{ force } ? 1 : 0 );
    if ( $need_result ) {
        return $do;
    }
    return '';
}

sub _hdlr_rebuild_indexbyblogid {
    my ( $ctx, $args, $cond ) = @_;
    $args->{ ArchiveType } = 'index';
    return _hdlr_rebuild_blog( $ctx, $args, $cond );
}

1;