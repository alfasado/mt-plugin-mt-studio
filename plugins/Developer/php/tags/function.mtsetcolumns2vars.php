<?php
function smarty_function_mtsetcolumns2vars ( $args, &$ctx ) {
    if ( isset( $args[ 'stash' ] ) ) $stash = $args[ 'stash' ];
    if (! $stash ) if ( isset( $args[ 'object' ] ) ) $stash = $args[ 'object' ];
    if ( isset( $args[ 'prefix' ] ) ) $prefix = $args[ 'prefix' ];
    if (! $prefix ) $prefix = '';
    $vars = $ctx->__stash[ 'vars' ];
    if (! $stash ) {
        if ( isset( $vars[ 'entry_archive' ] ) ) {
            $stash = 'entry';
        } elseif ( isset( $vars[ 'page_archive' ] ) ) {
            $stash = 'entry';
        }
    }
    if (! $stash ) $stash = 'blog';
    $obj = $ctx->stash( $stash );
    $arr = ( array ) $obj;
    foreach ( $arr as $key => $value ) {
        if ( is_string( $value ) ) {
            if ( strpos( $key, $stash . '_' ) === 0 ) {
                $key = preg_replace( "/^${stash}_/", "", $key );
                $ctx->__stash[ 'vars' ][ $prefix . $key ] = $value;
            }
        }
    }
    if ( $stash == 'entry' ) {
        require_once( 'function.mtentrypermalink.php' );
        $permalink = smarty_function_mtentrypermalink( $args, $ctx );
        $ctx->__stash[ 'vars' ][ $prefix . 'permalink' ] = $permalink;
    }
    return '';
}
?>