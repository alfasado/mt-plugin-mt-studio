<?php
function smarty_function_mtmljobname ( $args, &$ctx ) {
    require_once( 'function.mtmljobtitle.php' );
    return smarty_function_mtmljobtitle( $args, $ctx );
}
?>