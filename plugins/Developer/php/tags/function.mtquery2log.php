<?php
function smarty_function_mtquery2log ( $args, &$ctx ) {
    $app = $ctx->stash( bootstrapper );
    $message = $args[ 'message' ];
    if ( $message ) {
        $message .= ' : ';
    }
    $q = $app->query_string;
    if ( $args[ 'url' ] ) {
        if ( $q ) $sep = '?';
        $q = $app->base . $app->path . $app->script . $sep . $q;
    }
    $message .= $q;
    require_once( 'function.mtlog.php' );
    $args[ 'message' ] = $message;
    return smarty_function_mtlog( $args, $ctx );
    return '';
}
?>