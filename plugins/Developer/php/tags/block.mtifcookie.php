<?php
function smarty_block_mtifcookie ( $args, $content, &$ctx, &$repeat ) {
    $name = $args[ 'name' ];
    $cookie_val = $_COOKIE[ $name ];
    $ctx->__stash[ 'vars' ][ strtolower( $name ) ] = $cookie_val;
    $args[ 'name' ] = $name;
    require_once( 'block.mtif.php' );
    return smarty_block_mtif( $args, $content, $ctx, $repeat );
}
?>