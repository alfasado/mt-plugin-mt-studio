<?php
function smarty_function_mtmljobtitle ( $args, &$ctx ) {
    $job = $ctx->stash( 'mtmljob' );
    if (! $job ) {
        return '';
    }
    return $job->title;
}
?>