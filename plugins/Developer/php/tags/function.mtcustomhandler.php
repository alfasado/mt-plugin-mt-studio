<?php
function smarty_function_mtcustomhandler ( $args, &$ctx ) {
    require_once( 'function.mtmljob.php' );
    return smarty_function_mtmljob( $args, $ctx );
}
?>