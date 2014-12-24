<?php
function smarty_function_mtgetcookie ( $args, &$ctx ) {
    $name = $args[ 'name' ];
    return $_COOKIE[ $name ];
}
?>