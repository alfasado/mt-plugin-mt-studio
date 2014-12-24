<?php
function smarty_function_mtsetfields2vars ( $args, &$ctx ) {
    require_once( 'function.mtsetcolumns2vars.php' );
    return smarty_function_mtsetcolumns2vars( $args, $ctx );
}
?>