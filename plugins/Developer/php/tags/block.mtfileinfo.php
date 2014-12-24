<?php
function smarty_block_mtfileinfo ( $args, $content, &$ctx, &$repeat ) {
    $localvars = array( 'fi', 'fis', '_fis_counter' );
    $app = $ctx->stash( 'bootstrapper' );
    if (! isset( $content ) ) {
        $ctx->localize( $localvars );
        $ctx->__stash[ 'fis' ] = NULL;
    }
    $fis = $ctx->stash( 'fis' );
    $counter = $ctx->stash( '_fis_counter' );
    if (! isset( $fis ) ) {
        $include_blogs = $app->include_exclude_blogs( $ctx, $args );
        if (! $include_blogs ) $ctx->error( '' );
        $ctx->stash( 'include_blogs', $include_blogs );
        require_once( 'class.mt_fileinfo.php' );
        $_fileinfo = new FileInfo;
        $where = "fileinfo_blog_id ${include_blogs}";
        $fis = $_fileinfo->Find( $where, FALSE, FALSE, array() );
        $ctx->stash( 'fis', $fis );
        $counter = 0;
    }
    if ( isset( $args[ 'glue' ] ) {
        $glue = $args[ 'glue' ];
    }
    if ( $counter < count( $fis ) ) {
        $fi = $fis[ $counter ];
        $counter++;
        $ctx->stash( '_fis_counter', $counter );
        $ctx->stash( 'fileinfo', $fi );
        $cn = $fi->column_names;
        $fi = $fi->GetArray();
        foreach ( $fi as $key => $value ) {
            $ctx->__stash[ 'vars' ][ $key ] = $value;
        }
        $ctx->__stash[ 'vars' ][ '__counter__' ] = $counter;
        $ctx->__stash[ 'vars' ][ '__odd__' ]     = ( $counter % 2 ) == 1;
        $ctx->__stash[ 'vars' ][ '__even__' ]    = ( $counter % 2 ) == 0;
        $ctx->__stash[ 'vars' ][ '__first__' ]   = $counter == 1;
        $ctx->__stash[ 'vars' ][ '__last__' ]    = ( $counter == count( $fis ) );
        if ( $glue && ( $counter != count( $fis ) ) ) {
            $content .= $glue;
        }
        $repeat = TRUE;
    } else {
        $ctx->restore( $localvars );
        $repeat = FALSE;
    }
    return $content;
}
?>