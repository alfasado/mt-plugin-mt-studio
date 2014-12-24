<?php
function smarty_function_mtgetheader ( $args, &$ctx ) {
    $name = $args[ 'name' ];
    $headers = getallheaders();
    return $headers[ $name ];
}
?>