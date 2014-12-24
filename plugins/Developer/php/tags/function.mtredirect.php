<?php
function smarty_function_mtredirect ( $args, &$ctx ) {
    $url = $args[ 'url' ];
    header( 'Location: ' . $url );
}
?>