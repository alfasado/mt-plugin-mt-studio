<?php
function smarty_function_mtdeveloperscript ( $args, &$ctx ) {
    $app = $ctx->stash( 'bootstrapper' );
    if (! $app ) {
        $app = $ctx->mt;
    }
    $script = $app->config( 'DeveloperScript' );
    if ( $script ) return $script;
    return 'mt-app.cgi';
}
?>