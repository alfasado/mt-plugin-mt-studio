<?php
function smarty_function_mtlog ( $args, &$ctx ) {
    $app = $ctx->stash( bootstrapper );
    $message = $args[ 'message' ];
    $level = $args[ 'level' ];
    if (! $level ) $level = 16;
    $category = $args[ 'category' ];
    if (! $category ) $category = 'developer';
    $params = array();
    $params[ 'level' ] = $level;
    $params[ 'category' ] = $category;
    $blog_id = $args[ 'blog_id' ];
    if (! $blog_id ) {
        if ( $ctx->stash( 'blog' ) ) {
            $blog_id = $ctx->stash( 'blog' )->id;
        }
    }
    if ( $blog_id ) {
        $params[ 'blog_id' ] = $blog_id;
    }
    if ( $app->user ) {
        $params[ 'author_id' ] = $app->user->id;
    }
    $params[ 'ip' ] = $app->remote_ip;
    $app->log( $message, $params );
    $print = $args[ 'print' ];
    if (! $print ) $print = $args[ 'echo' ];
    if ( $print ) {
        return $message;
    }
    return '';
}
?>