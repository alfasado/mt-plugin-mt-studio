<?php
function smarty_function_mtgetenv ( $args, &$ctx ) {
    $env = $args[ 'name' ];
    return $_SERVER[ $env ];
}
?>