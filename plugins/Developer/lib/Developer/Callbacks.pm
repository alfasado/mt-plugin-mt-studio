package Developer::Callbacks;

use strict;
use warnings;

use Developer::Util qw( _trim app_ref2id src2sub );

use MT::Log;
use File::Find;
use MT::Builder;
use MT::Template::Context;
use File::Temp qw( tempdir );
# use MIME::Base64 ();
our @__developer_loaded_custom_handlers;

sub _post_init {
    my $app = MT->instance;
    if ( ( ref $app ) eq 'MT::App::CMS' ) {
        if ( $app->mode && $app->mode eq 'disable_customhandlers' ) {
            return 1;
        } elsif ( $app->mode && $app->mode eq 'disable_alttemplates' ) {
            return 1;
        } elsif ( $app->mode && $app->mode eq 'export_studio_player' ) {
            return 1;
        }
    }
    my @jobs = MT->model( 'mtmljob' )->load( { interval => [ 7, 8, 10, 11, 12 ], status => 2 },
                                             { sort => 'priority', direction => 'ascend' } );
    # my @yamls = MT->model( 'mtmljob' )->load( { interval => 12, status => 2 } );
    my @yamls;
    my @plugins;
    if ( @jobs ) {
        for my $job( @jobs ) {
            if ( $job->interval == 12 ) {
                push( @yamls, $job );
            } else {
                push( @plugins, $job );
            }
        }
        if ( @yamls ) {
            my $tempdir = MT->config( 'TempDir' );
            $tempdir = tempdir( DIR => $tempdir );
            require MT::FileMgr;
            my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
            $tempdir =~ s!/$!! unless $tempdir eq '/';
            $fmgr->mkpath( $tempdir ) or return undef;
            for my $yaml( @yamls ) {
                # my $registry = MT::Util::YAML::Load( $yaml->text );
                # $registry->{ id } = $yaml->basename;
                # my $plugin = MT::Plugin->new( $registry );
                # MT->add_plugin( $plugin );
                # $plugin->init_callbacks();
                my $plugin_dir = File::Spec->catdir( $tempdir, $yaml->basename );
                $plugin_dir =~ s!/$!! unless $plugin_dir eq '/';
                $fmgr->mkpath( $plugin_dir ) or return undef;
                my $config_yaml = File::Spec->catfile( $plugin_dir, 'config.yaml' );
                $fmgr->put_data( $yaml->text, $config_yaml );
            }
            my $plugins_dir = $tempdir;
            MT->_init_plugins_core( {}, 1, [ $plugins_dir ] );
            File::Path::rmtree( [ $tempdir ] );
        }
    }
    @__developer_loaded_custom_handlers = @plugins;
}

sub _init_plugin {
    my $app = MT->instance();
    if ( ref( $app ) =~ /^MT::App/ ) {
        return 1 if $_[0]->name eq 'init_app';
    }
    return 1 if ( ref $app ) eq 'MT::App::Upgrader';
    if ( ( ref $app ) eq 'MT::App::CMS' ) {
        if ( $app->mode && $app->mode eq 'disable_customhandlers' ) {
            return 1;
        } elsif ( $app->mode && $app->mode eq 'disable_alttemplates' ) {
            return 1;
        } elsif ( $app->mode && $app->mode eq 'export_studio_player' ) {
            return 1;
        }
    }
    my $cache = MT->request( 'plugin-developer-init' );
    return 1 if $cache;
    my $allow_perl = $app->config( 'AllowPerlScript' );
    MT->request( 'plugin-developer-init', 1 );
    # if ( my $auth = $app->get_header( 'AUTHORIZATION' ) ) {
    #     my @auths = split( /\s/, $auth );
    #     $auth = $auths[ 1 ];
    #     $auth = MIME::Base64::decode_base64( $auth );
    #     $app->response_code( '401' );
    #     $app->set_header( 'WWW-Authenticate', 'Basic realm="Please entry your ID and Password"' );
    # }
    my $component = MT->component( 'Developer' );
    my @jobs;
    if ( @__developer_loaded_custom_handlers ) {
        @jobs = @__developer_loaded_custom_handlers;
    } else {
        @jobs = MT->model( 'mtmljob' )->load( { interval => [ 7, 8, 10, 11 ], status => 2 },
                                              { sort => 'priority', direction => 'ascend' } );
    }
    my $block_tags = $component->registry( 'tags', 'block' );
    my $function_tags = $component->registry( 'tags', 'function' );
    my $global_modifiers = $component->registry( 'tags', 'modifier' );
    my @callbacks;
    my $_endpoint = $component->registry( 'applications' )->{ data_api }->{ endpoints };
    my @endpoints = @$_endpoint;
    for my $job( @jobs ) {
        my $detail = $job->detail;
        if ( $job->interval == 7 ) {
            my @details = split( /,/, $detail );
            my $data = $job->text;
            if ( $job->evalscript && $allow_perl ) {
                $data = src2sub( $data );
                # $data = _trim( $data );
                # if ( $data !~ m/^sub/m ) {
                #     $data = "sub {\n" . $data . "\n}";
                # } else {
                #     $data =~ s/^sub[^\{]{0,}/sub /;
                # }
            }
            for my $d ( @details ) {
                $d = MT::Util::trim( $d );
                if ( $job->evalscript && $allow_perl ) {
                    MT->add_callback( $d, $job->priority, $component, MT->handler_to_coderef( $data ) );
                } else {
                    MT->add_callback( $d, $job->priority, $component, \&_do_callback );
                    push( @callbacks, $job );
                }
            }
        } elsif ( $job->interval == 11 ) {
            if ( ( ref $app ) eq 'MT::App::DataAPI' ) {
                require MT::DataAPI::Endpoint::Common;
                require MT::DataAPI::Resource;
                my $endpoint = { id => $job->basename };
                my $data = $job->text;
                my $handler;
                if ( $job->evalscript && $allow_perl ) {
                    $data = src2sub( $data );
                    # $data = _trim( $data );
                    # if ( $data !~ m/^sub/m ) {
                    #     $data = "sub {\n" . $data . "\n}";
                    # } else {
                    #     $data =~ s/^sub[^\{]{0,}/sub /;
                    # }
                    $handler = MT->handler_to_coderef( $data );
                } else {
                    $handler = sub {
                            return __build_app( $app, $job );
                        };
                }
                $endpoint->{ handler } = $handler;
                my ( $verb, $route ) = split( /,/, $detail );
                if (! $route ) {
                    $verb = 'GET';
                    $route = $verb;
                }
                my $version = $component->get_config_value( 'developer_data_api_version' ) || 1;
                $version =~ s/[^0-9]//g;
                my $requires_login = $job->requires_login || 0;
                $endpoint->{ requires_login } = $requires_login;
                $endpoint->{ verb } = _trim( $verb );
                $endpoint->{ route } = _trim( $route );
                $endpoint->{ version } = $version;
                push( @endpoints, $endpoint );
                # $component->registry( 'applications' )->{ data_api }->{ endpoints } = [ $endpoint ];
            }
        } elsif ( $job->interval == 10 ) {
            if ( ( ref $app ) eq $job->app_ref ) {
                my $meth_name = $job->detail;
                my @meth_names = split( /,/, $meth_name );
                my $data = $job->text;
                my $method;
                if ( $job->evalscript && $allow_perl ) {
                    $data = src2sub( $data );
                    # $data = _trim( $data );
                    # if ( $data !~ m/^sub/m ) {
                    #     $data = "sub {\n" . $data . "\n}";
                    # } else {
                    #     $data =~ s/^sub[^\{]{0,}/sub /;
                    # }
                    $method = MT->handler_to_coderef( $data );
                }
                for my $meth ( @meth_names ) {
                    if ( ( ref $app ) =~ /^MT::App/ ) {
                        if ( $app->mode && $app->mode eq $meth ) {
                            if ( $job->requires_login ) {
                                $app->{ requires_login } = 1;
                            }
                        }
                    }
                    if ( $job->evalscript && $allow_perl ) {
                        $app->add_methods( $meth => $method );
                        # $app->registry( 'applications' )->{
                        #     app_ref2id( $job->app_ref ) }->{ methods }->{ $meth }
                        #         = { code => $method, requires_login => $job->requires_login };
                    } else {
                        $app->add_methods( $meth => sub {
                            return __build_app( $app, $job );
                        } );
                    }
                }
            }
        } elsif ( $job->interval == 8 ) {
            # Tags
            my $tagkind = $job->tagkind;
            next unless $tagkind;
            my $tag_name = $job->detail;
            next unless $tag_name;
            my $orig_tag = $tag_name;
            $tag_name = lc( $tag_name );
            if ( $tagkind ne 'modifier' ) {
                $tag_name =~ s/^mt//i;
                $orig_tag =~ s/^mt//i;
            }
            my $data = $job->text;
            if ( $job->evalscript && $allow_perl ) {
                $data = src2sub( $data );
                # $data = _trim( $data );
                # if ( $data !~ m/^sub/m ) {
                #     $data = "sub {\n" . $data . "\n}";
                # } else {
                #     $data =~ s/^sub[^\{]{0,}/sub /;
                # }
                if ( $tagkind eq 'function' ) {
                    $function_tags->{ $orig_tag } = MT->handler_to_coderef( $data );
                } elsif ( $tagkind eq 'block' ) {
                    $block_tags->{ $orig_tag } = MT->handler_to_coderef( $data );
                } elsif ( $tagkind eq 'conditional' ) {
                    if ( $tag_name !~ m/\?$/ ) {
                        $tag_name .= '?';
                    }
                    $block_tags->{ $orig_tag } = MT->handler_to_coderef( $data );
                } elsif ( $tagkind eq 'modifier' ) {
                    $global_modifiers->{ $orig_tag } = MT->handler_to_coderef( $data );
                }
            } else {
                if ( $tagkind eq 'function' ) {
                    $function_tags->{ $tag_name } = sub {
                        my ( $ctx, $args, $cond ) = @_;
                        my $app = MT->instance;
                        my $tag = $ctx->stash( 'tag' );
                        my $template = $job->text;
                        return __build( $tag, $ctx, $args, $template );
                    };
                } elsif ( $tagkind eq 'block' ) {
                    $block_tags->{ $tag_name } = sub {
                        my ( $ctx, $args, $cond ) = @_;
                        my $app = MT->instance;
                        my $tag = $ctx->stash( 'tag' );
                        ## TODO:: Set $args to $vars;
                        my $template = $job->text;
                        return __build( $tag, $ctx, $args, $template );
                    };
                } elsif ( $tagkind eq 'conditional' ) {
                    if ( $tag_name !~ m/\?$/ ) {
                        $tag_name .= '?';
                    }
                    $block_tags->{ $tag_name } = sub {
                        my ( $ctx, $args, $cond ) = @_;
                        my $app = MT->instance;
                        my $tag = $ctx->stash( 'tag' );
                        my $template = $job->text;
                        my $out =  __build( $tag, $ctx, $args, $template );
                        if ( $out ) {
                            return 1;
                        } else {
                            return 0;
                        }
                    };
                } elsif ( $tagkind eq 'modifier' ) {
                    $global_modifiers->{ $tag_name } = sub { 
                        my ( $text, $arg, $ctx ) = @_;
                        my $app = MT->instance;
                        $ctx->{ __stash }{ vars }{ $tag_name . '.text' } = $text;
                        $ctx->{ __stash }{ vars }{ $tag_name . '.arg' } = $arg;
                        my $template = $job->text;
                        return __build( $tag_name, $ctx, $arg, $template );
                    };
                }
            }
        }
    }
    if ( scalar( @endpoints ) ) {
        $component->registry( 'applications' )->{ data_api }->{ endpoints } = \@endpoints;
    }
    MT->request( 'RegisterCallbacks', \@callbacks );
    my @alttemplates = MT->model( 'alttemplate' )->load( { status => 2 } );
    for my $alt_tmpl ( @alttemplates ) {
        if ( my $template = $alt_tmpl->template ) {
            my $template = 'template_source.' . $template;
            if ( my $app_ref = $alt_tmpl->app_ref ) {
                $template = $app_ref . '::' . $template;
            }
            MT->add_callback( $template, 5, $component,  sub { 
                my ( $cb, $app, $tmpl ) = @_;
                $$tmpl = $alt_tmpl->text;
            } );
        }
    }
    my $tags_dir = File::Spec->catdir( $component->path, 'perl' );
    if ( -d $tags_dir ) {
        opendir( DIR, $tags_dir );
        my @tags = readdir( DIR );
        closedir( DIR );
        for my $tag( @tags ) {
            next if ( $tag =~ /^\./ );
            my $file = File::Spec->catfile( $tags_dir, $tag );
            my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
            my $data = $fmgr->get_data( $file );
            my @item = split( /\./, $tag );
            my $kind = $item[ 0 ];
            my $tag_name = $item[ 1 ];
            $tag_name =~ s/^mt//i;
            if ( $kind eq 'block' ) {
                if ( $tag_name =~ m/^if/ ) {
                    $tag_name .= '?';
                } 
                $block_tags->{ $tag_name } = MT->handler_to_coderef( $data );
            } elsif ( $kind eq 'function' ) {
                $function_tags->{ $tag_name } = MT->handler_to_coderef( $data );
            } elsif ( $kind eq 'modifier' ) {
                $global_modifiers->{ $tag_name } = MT->handler_to_coderef( $data );
            }
        }
    }
    if ( ( ref $app ) !~ /^MT::App/ ) {
        return;
    }
    if ( $app->mode && $app->mode eq 'preview_mtmljob' ) {
        my $interval = $app->param( 'interval' ) || 0;
        if ( $interval == 12 ) {
            # config.yaml
            return;
        }
        my $do_perl;
        my $freq;
        my $job = MT->model( 'mtmljob' )->new;
        my $out = $app->param( 'text' );
        if ( $app->param( 'evalscript' ) && $allow_perl ) {
            $out = src2sub( $out );
            # $out = _trim( $out );
            # if ( $out !~ m/^sub/m ) {
            #     $out = "sub {\n" . $out . "\n}";
            # } else {
            #     $out =~ s/^sub[^\{]{0,}/sub /;
            # }
            $freq = MT->handler_to_coderef( $out );
            if ( $app->config( 'DoCommandInPreview' ) ) {
                $do_perl = 1;
            }
        } else {
            $job->title( $app->param( 'title' ) );
            $job->id( $app->param( 'id' ) );
            $job->text( $app->param( 'text' ) );
            my @params = $app->param;
            for my $name ( @params ) {
                next unless $name;
                if ( $name =~ /^customfield_(.*$)/ ) {
                    my $basename = 'field.'. $1;
                    my $value = $app->param( $name );
                    if ( $job->has_column( $basename ) ) {
                        $job->$basename( $value );
                    }
                }
            }
        }
        if ( $interval == 8 ) {
            my $tag_name = $app->param( 'detail' );
            if ( my $tagkind = $app->param( 'tagkind' ) ) {
                $tag_name = lc( $tag_name );
                if ( $tagkind ne 'modifier' ) {
                    $tag_name =~ s/^mt//i;
                }
                if ( $tagkind eq 'function' ) {
                    if ( $do_perl ) {
                        $function_tags->{ $tag_name } = $freq;
                    } else {
                        $function_tags->{ $tag_name } = sub {
                            my ( $ctx, $args, $cond ) = @_;
                            my $tag = $ctx->stash( 'tag' );
                            my $template = $job->text;
                            return __build( $tag, $ctx, $args, $template );
                        };
                    }
                } elsif ( $tagkind eq 'block' ) {
                    if ( $do_perl ) {
                        $block_tags->{ $tag_name } = $freq;
                    } else {
                        $block_tags->{ $tag_name } = sub {
                            my ( $ctx, $args, $cond ) = @_;
                            my $tag = $ctx->stash( 'tag' );
                            my $template = $job->text;
                            return __build( $tag, $ctx, $args, $template );
                        };
                    }
                } elsif ( $tagkind eq 'conditional' ) {
                    if ( $tag_name !~ m/\?$/ ) {
                        $tag_name .= '?';
                    }
                    if ( $do_perl ) {
                        $block_tags->{ $tag_name } = $freq;
                    } else {
                        $block_tags->{ $tag_name } = sub {
                            my ( $ctx, $args, $cond ) = @_;
                            my $tag = $ctx->stash( 'tag' );
                            my $template = $job->text;
                            return __build( $tag, $ctx, $args, $template );
                        };
                    }
                } elsif ( $tagkind eq 'modifier' ) {
                    if ( $do_perl ) {
                        $global_modifiers->{ $tag_name } = $freq;
                    } else {
                        $global_modifiers->{ $tag_name } = sub { 
                            my ( $text, $arg, $ctx ) = @_;
                            my $app = MT->instance;
                            $ctx->{ __stash }{ vars }{ $tag_name . '.text' } = $text;
                            $ctx->{ __stash }{ vars }{ $tag_name . '.arg' } = $arg;
                            my $template = $job->text;
                            return __build( $tag_name, $ctx, $arg, $template );
                        };
                    }
                }
            }
        }
    }
}

sub __build_app {
    my ( $app, $job ) = @_;
    my $component = MT->component( 'Developer' );
    my $ctx = MT::Template::Context->new;
    $ctx->stash( 'mtmljob', $job );
    my $template = $job->text;
    my $app_ref = ref $app;
    my $tmpl = MT->model( 'template' )->new;
    $tmpl->text( $template );
    if ( $app_ref eq 'MT::App::CMS' ) {
        $app->set_default_tmpl_params( $tmpl );
    }
    MT->run_callbacks( $app_ref . '::template_cource.' . $job->basename, $app, \$template );
    my $params = $tmpl->param;
    $tmpl->text( $template );
    MT->run_callbacks( $app_ref . '::template_param.' . $job->basename, $app, $params, $tmpl );
    my $output = $app->build_page( $tmpl, $params );
    MT->run_callbacks( $app_ref . '::template_output.' . $job->basename, $app, \$output, $params, $tmpl );
    return $output;
    # my $build = MT::Builder->new;
    # my $tokens = $build->compile( $ctx, $template )
    #     or $app->log( $component->translate(
    #         'Parse error: [_1]', $build->errstr ) );
    # defined( my $out = $build->build( $ctx, $tokens ) )
    #     or $app->log( $component->translate(
    #         'Build error: [_1]', $build->errstr ) );
    # $out;
}

sub __build {
    my ( $tag, $ctx, $args, $template ) = @_;
    my $component = MT->component( 'Developer' );
    $tag = lc( $tag );
    my $app = MT->instance;
    if ( ( ref $args ) eq 'HASH' ) {
        for my $key ( keys %$args ) {
            if ( $key ne '@' ) {
                $ctx->{ __stash }{ vars }{ $tag . '.' . $key } = $args->{ $key };
            }
        }
    }
    my $build = MT::Builder->new;
    my $tokens = $build->compile( $ctx, $template )
        or $app->log( $component->translate(
            'Parse error: [_1]', $build->errstr ) );
    defined( my $out = $build->build( $ctx, $tokens ) )
        or $app->log( $component->translate(
            'Build error: [_1]', $build->errstr ) );
    $out;
}

sub _do_callback {
    my $cb = shift;
    my $component = MT->component( 'Developer' );
    my @params = @_;
    my $meth = $cb->method;
    if ( MT->request( 'DoCallback:' . $meth ) ) {
        return 1;
    }
    MT->request( 'DoCallback:' . $meth, 1 );
    my $jobs = MT->request( 'RegisterCallbacks' );
    if (! $jobs ) {
        my @mtml_jobs = MT->model( 'mtmljob' )->load( { detail => { like => '%' . $meth . '%' } } );
        $jobs = \@mtml_jobs;
    }
    my $allow_perl =  MT->config( 'AllowPerlScript' );
    $meth = quotemeta( $meth );
    for my $job ( @$jobs ) {
        my $detail = $job->detail;
        my @details = split( /,/, $detail );
        if ( grep( /^$meth$/, @details ) ) {
            my $template = $job->text;
            if ( $job->evalscript && $allow_perl ) {
                $template = _trim( $template );
                my $freq = MT->handler_to_coderef( $template );
                if ( $template !~ m/sub\s{0,}\{/m ) {
                    $template = "sub {\n" . $template . "\n}";
                }
                $freq = $freq->( $cb, @_ );
                next;
            }
            $template = MT->instance->translate_templatized( $template );
            my $app = MT->instance;
            require MT::Template::Context;
            require MT::Builder;
            my $ctx = MT::Template::Context->new;
            $ctx->stash( 'mtmljob', $job );
            my ( $model, $rebuild );
            if ( $cb->method =~ m/^cms_.*?\.(.*?)$/ ) {
                $model = $1;
            } elsif ( $cb->method =~ m/^api_.*?\.(.*?)$/ ) {
                $model = $1;
            } elsif ( $cb->method =~ m/^build_.*$/ ) {
                $rebuild = 1;
            }
            my $blog;
            if ( ( ref $app ) =~ /^MT::App::/ ) {
                if ( $app->blog ) {
                    $blog = $app->blog;
                }
            }
            if ( $model ) {
                my $obj = $params[ 1 ];
                my $original = $params[ 2 ];
                if ( defined $obj ) {
                    my $ds = $obj->datasource;
                    $ctx->stash( $ds, $obj );
                    if (! $blog ) {
                        if ( ( $obj->has_column( 'blog_id' ) ) && ( $obj->blog_id ) ) {
                            require MT::Blog;
                            $blog = MT::Blog->load( $obj->blog_id );
                        }
                    }
                    if ( $obj->has_column( 'status' ) ) {
                        $ctx->{ __stash }{ vars }{ new_status } = $obj->status;
                    }
                }
                if ( defined $original ) {
                    if ( $original->has_column( 'status' ) ) {
                        $ctx->{ __stash }{ vars }{ old_status } = $original->status;
                    }
                }
            }
            if ( $blog ) {
                $ctx->stash( 'blog', $blog );
                $ctx->stash( 'blog_id', $blog->id );
            }
            if ( $rebuild ) {
                my %args = @_;
                if ( my $context = $args{ Context } ) {
                    $ctx = $context;
                }
                if ( my $file = $args{ File } ) {
                    $ctx->{ __stash }{ vars }{ publishing_file } = $file;
                }
            }
            my $build = MT::Builder->new;
            my $tokens = $build->compile( $ctx, $template )
                or $app->log( $component->translate(
                    'Parse error: [_1]', $build->errstr ) );
            defined( my $out = $build->build( $ctx, $tokens ) )
                or $app->log( $component->translate(
                    'Build error: [_1]', $build->errstr ) );
            return $out;
        }
    }
    return 1;
}

sub _pre_run {
    my $app = MT->instance;
    if ( ( ref $app ) !~ /^MT::App::/ ) {
        return;
    }
    if ( $app->user && $app->user->is_superuser ) {
        my $disable_object_methods = $app->registry( 'disable_object_methods' );
        $disable_object_methods->{ 'log' }->{ 'delete' } = undef;
    }
}

sub _post_run_debug {
    my $app = MT->instance;
    if ( ( ref $app ) !~ /^MT::App::/ ) {
        return;
    }
    if ( my $level = MT->config( 'Query2LogDebugMode' ) ) {
        if ( $level == 1 && ( $app->request_method eq 'GET'
            || $app->mode eq 'filtered_list' ) ) {
            return;
        }
        $app->log( {
                message => MT->instance->query_string,
                catgory => 'query2log',
                level => MT::Log::DEBUG(),
        } );
    }
}

sub _reset_request {
    require MT::Request;
    my $r = MT::Request->instance;
    $r->reset();
}

sub _error {
    my ( $cb, $app, $param, $tmpl ) = @_;
    if ( MT->config( 'Query2LogAtError' ) ) {
        my $query = MT->instance->query_string || '';
        my $error = $param->{ error } || '';
        $app->log( {
                message => $error . ' : ' . $query,
                catgory => 'query2log',
                level => MT::Log::ERROR(),
        } );
    }
}

sub _error_log {
    my ( $cb, $obj ) = @_;
    my $app = MT->instance;
    if ( ( ref $app ) !~ /^MT::App::/ ) {
        return 1;
    }
    return 1 if ( $obj->level && $obj->level != MT::Log::ERROR() );
    return 1 if ( $obj->category && $obj->category eq 'query2log' );
    if ( MT->config( 'Query2LogAtError' ) ) {
        $app->log( {
                message => $obj->message .
                ' : ' . $app->query_string,
                catgory => 'query2log',
                level => MT::Log::ERROR(),
        } );
    }
    return 1;
}

sub _cb_gzip {
    my ( $cb, %args ) = @_;
    if ( MT->config( 'Content2Gzip' ) ) {
        my $content = $args{ content };
        my $file = $args{ file };
        my @extentions = split( /,/, MT->config( 'Content2GzipExtensions' ) );
        my $extension = '';
        if ( $file =~ /\.([^.]+)\z/ ) {
            $extension = lc( $1 );
        } else {
            return
        }
        if ( grep( /^$extension$/, @extentions ) ) {
            require IO::Compress::Gzip;
            my $output;
            my $data = $content = MT::I18N::utf8_off( $$content );
            IO::Compress::Gzip::gzip( \$data, \$output, Minimal => 1 );
            require MT::FileMgr;
            my $fmgr = MT::FileMgr->new( 'Local' );
            $fmgr->put_data( $output, $file . '.gz', 'upload' );
        }
    }
}

sub _cb_delete_archive {
    my ( $cb, $file, $at, $entry ) = @_;
    if ( MT->config( 'Content2Gzip' ) ) {
        my @extentions = split( /,/, MT->config( 'Content2GzipExtensions' ) );
        my $extension = '';
        if ( $file =~ /\.([^.]+)\z/ ) {
            $extension = lc( $1 );
        } else {
            return
        }
        if ( grep( /^$extension$/, @extentions ) ) {
            require MT::FileMgr;
            my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
            if ( $fmgr->exists( $file . '.gz' ) ) {
                $fmgr->delete( $file . '.gz' );
            }
        }
    }
    return 1;
}

sub _cb_remove_exif {
    my ( $cb, %args ) = @_;
    if ( MT->config( 'RemoveExifAtUploadImage' ) ) {
        my $asset = $args{ asset };
        my $photo = $asset->file_path;
        require Image::Magick;
        my $image = Image::Magick->new();
        $image->Read( $photo );
        $image->Strip();
        $image->Write( "${photo}.new" );
        require MT::FileMgr;
        my $fmgr = MT::FileMgr->new( 'Local' ) or die MT::FileMgr->errstr;
        if ( $fmgr->file_size( "${photo}.new" ) < $fmgr->file_size( $photo ) ) {
            $fmgr->rename( "${photo}.new", $photo );
        } else {
            $fmgr->delete( "${photo}.new" );
        }
    }
    return 1;
}

sub _build_file_filter {
    my ( $cb, %args ) = @_;
    my $file  = $args{ File };
    my $ctx = $args{ Context };
    $ctx->stash( 'current_archive_file', $file );
    return 1;
}

sub _save_cf_callback {
    eval {
        return CustomFields::App::CMS::CMSPostSave_customfield_objs( @_ );
    };
    return 1;
}

1;