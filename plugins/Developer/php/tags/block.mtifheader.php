<?php
function smarty_block_mtifheader ( $args, $content, &$ctx, &$repeat ) {
    $name = $args[ 'name' ];
    $headers = getallheaders();
    $header = $headers[ $name ];
    $ctx->__stash[ 'vars' ][ strtolower( $key ) ] = $header;
    $args[ 'name' ] = $header;
    require_once( 'block.mtif.php' );
    return smarty_block_mtif( $args, $content, $ctx, $repeat );
}
?>