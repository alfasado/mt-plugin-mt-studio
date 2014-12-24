package Developer::DataAPI;

use strict;
use warnings;

use MT::Log;
use MT::DataAPI::Endpoint::Common;
use MT::DataAPI::Resource;
use MT::Builder;
use MT::Template::Context;
use Developer::Util qw( data_api_setup_terms data_api_setup_args );

sub _handler_data_api_get_logs {
    my ( $app, $endpoint ) = @_;
    my ( $blog ) = context_objects( @_ );
    if ( $endpoint->{ requires_login } ) {
        my $user = $app->user;
        if (! $user || $user->is_anonymous ) {
            return $app->print_error( 'Unauthorized', 401 );
        } else {
            my $perm = $user->is_superuser;
            if (! $perm ) {
                if ( $blog ) {
                    my $admin = 'can_administer_blog';
                    $perm = $user->permissions( $blog->id )->$admin;
                    $perm = $user->permissions( $blog->id )->view_blog_log unless $perm;
                } else {
                    $perm = $user->permissions()->view_log;
                }
            }
            if (! $perm ) {
                return $app->print_error( 'Permission denied.', 401 );
            }
        }
    }
    my $terms = data_api_setup_terms( $app, $endpoint, 'log' );
    my $count = MT->model( 'log' )->count( $terms );
    my $args = data_api_setup_args( $app, $endpoint, 'log' );
    my @logs = MT->model( 'log' )->load( $terms, $args );
    if (! $app->param( 'fields' ) ) {
        my $fields = 'id,message,created_on,category,lebel,ip,author_id,metadata';
        $app->param( 'fields', $fields );
    }
    my @result_objects;
    for my $log ( @logs ) {
        $log->class( undef );
        push( @result_objects, $log );
    }
    return {
        totalResults => $count,
        items => \@result_objects,
    };
    return 1;
}

sub _handler_mtmlcompile {
    my ( $app, $endpoint ) = @_;
    my $component = MT->component( 'Developer' );
    my ( $blog ) = context_objects( @_ );
    my $user = $app->user;
    if (! $user || $user->is_anonymous ) {
        return $app->print_error( 'Unauthorized', 401 );
    } else {
        my $perm = $user->is_superuser;
        if (! $perm ) {
            if ( $blog ) {
                my $admin = 'can_administer_blog';
                $perm = $user->permissions( $blog->id )->$admin;
                $perm = $user->permissions( $blog->id )->edit_template unless $perm;
            } else {
                $perm = $user->permissions()->edit_template;
            }
        }
        if (! $perm ) {
            return $app->print_error( 'Permission denied.', 401 );
        }
    }
    my $res;
    my $mtml = $app->param( 'mtml' ) || $app->param( 'MTML' );
    if (! $mtml ) {
        $res->{ code } = 200;
        $res->{ message } = $component->translate( 'No MTML given.' );
        return $res;
    }
    my $template = MT->model( 'template' )->new;
    my $blog_id = 0;
    $blog_id = $blog->id if $blog ;
    $template->blog_id( $blog_id );
    $template->text( $mtml );
    $template->compile;
    if ( $template->{ errors } && @{ $template->{ errors } } ) {
        $res->{ error }->{ code } = 500;
        $res->{ error }->{ message } = MT->translate( 'One or more errors were found in this template.' );
        my @errors;
        foreach my $err ( @{ $template->{ errors } } ) {
            push( @errors, $err->{ message } );
        }
        $res->{ errors } = \@errors;
        return $res;
    }
    my $error_message;
    if ( $app->param( 'build_result' ) ) {
        my $ctx = MT::Template::Context->new;
        $ctx->stash( 'blog', $blog );
        my $build = MT::Builder->new;
        my $tokens = $build->compile( $ctx, $template->text )
            or $error_message = $component->translate(
                'Parse error: [_1]', $build->errstr );
        defined( my $out = $build->build( $ctx, $tokens ) )
            or $error_message = $component->translate(
                'Build error: [_1]', $build->errstr );
        if ( $error_message ) {
            $res->{ error }->{ code } = 500;
            $res->{ message } = $error_message;
            return $res;
        }
        $res->{ build_result } = $out;
    }
    $res->{ code } = 200;
    $res->{ message } = $component->translate( 'Template compile successfully.' );
    $res;
}

1;