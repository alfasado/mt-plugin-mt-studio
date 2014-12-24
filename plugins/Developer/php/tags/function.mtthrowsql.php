<?php
function smarty_function_mtthrowsql ( $args, &$ctx ) {
    if (! $ctx->mt->config( 'AllowThrowSQL' ) ) {
        return '';
    }
    $query = $args[ 'query' ];
    if (! $query ) {
        return '';
    }
    $ctx->mt->db()->execute( $query );
    return '';
}
?>