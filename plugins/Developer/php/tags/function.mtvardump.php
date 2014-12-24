<?php
function smarty_function_mtvardump ( $args, &$ctx ) {
    $name = $args[ 'name' ];
    if (! $name ) {
        ob_start();
        var_dump( $ctx->__stash[ 'vars' ] );
        $dump = ob_get_contents();
        ob_end_clean();
    } else {
        ob_start();
        var_dump( $ctx->__stash[ 'vars' ][ $name ] );
        $dump = ob_get_contents();
        ob_end_clean();
    }
    require_once( 'MTUtil.php' );
    $dump = encode_html( $dump );
    if (! $name ) {
        $dump = '<pre><code style="overflow:auto">' . $dump . '</code></pre>';
    } else {
        $dump = '<pre><code style="overflow:auto">' . $name . ' =&gt; ' . $dump . '</code></pre>';
    }
    return $dump;
}
?>