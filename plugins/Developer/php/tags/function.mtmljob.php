<?php
function smarty_function_mtmljob ( $args, &$ctx ) {
    if ( isset( $args[ 'name' ] ) ) {
        $name = $args[ 'name' ];
    } else if ( isset( $args[ 'title' ] ) ) {
        $name = $args[ 'title' ];
    }
    if ( isset( $args[ 'id' ] ) ) {
        $id = $args[ 'id' ];
    }
    if ( (! $name ) && (! $id ) ) {
        return '';
    }
    require_once( 'class.mt_mtmljob.php' );
    $job = new MTMLJob;
    if ( $id ) {
        $job->load( $id );
    } else {
        $job->load( "mtmljob_title='$name'" );
    }
    if (! $job ) {
        return '';
    }
    $ctx->stash( 'mtmljob', $job );
    require_once( 'modifier.mteval.php' );
    $contents = smarty_modifier_mteval( $job->text, TRUE );
    return $contents;
}
?>