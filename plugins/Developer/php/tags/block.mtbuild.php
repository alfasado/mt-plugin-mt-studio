<?php
function smarty_block_mtbuild ( $args, $content, &$ctx, &$repeat ) {
    $no_output = $args[ 'no_output' ];
    if (! $no_output ) {
        return $content;
    }
    return '';
}
?>