<?php
function smarty_block_mtfileinfoloop ( $args, $content, &$ctx, &$repeat ) {
    require_once( 'block.mtfileinfo.php' );
    return smarty_block_mtfileinfo( $args, $content, $ctx, $repeat );
}
?>